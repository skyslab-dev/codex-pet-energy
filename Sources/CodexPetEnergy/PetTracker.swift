import AppKit
import CoreGraphics

struct PetPlacement: Equatable {
    let mascotRect: CGRect
    let screenFrame: CGRect
}

enum OverlayPositioner {
    static func frame(for panelSize: CGSize, beside placement: PetPlacement, gap: CGFloat = 12) -> CGRect {
        let mascot = placement.mascotRect
        let screen = placement.screenFrame
        let rightX = mascot.maxX + gap
        let leftX = mascot.minX - gap - panelSize.width
        let x: CGFloat
        if rightX + panelSize.width <= screen.maxX - 8 {
            x = rightX
        } else if leftX >= screen.minX + 8 {
            x = leftX
        } else {
            x = min(max(rightX, screen.minX + 8), screen.maxX - panelSize.width - 8)
        }
        let centeredY = mascot.midY - panelSize.height / 2
        let y = min(max(centeredY, screen.minY + 8), screen.maxY - panelSize.height - 8)
        return CGRect(origin: CGPoint(x: x, y: y), size: panelSize)
    }
}

@MainActor
final class PetTracker: NSObject {
    struct LivePetWindow {
        let id: CGWindowID
        let rect: CGRect
    }

    struct PersistedPetState {
        let isOpen: Bool
        let windowRect: CGRect
        let mascotOffset: CGRect
    }

    private let stateURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".codex/.codex-global-state.json")
    private var timer: Timer?
    private var lastState: PersistedPetState?
    private var lastStateReadAt = Date.distantPast
    private var lastWindowPollAt = Date.distantPast
    private var lastPlacement: PetPlacement?
    private var wasPointerNearPet = false
    private var liveWindowID: CGWindowID?
    var onPlacement: ((PetPlacement?) -> Void)?

    func start() {
        tick()
        let timer = Timer(
            timeInterval: 0.04,
            target: self,
            selector: #selector(timerDidFire),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func timerDidFire() {
        tick()
    }

    func stop() {
        timer?.invalidate()
    }

    private func tick() {
        let now = Date()
        if lastState == nil || now.timeIntervalSince(lastStateReadAt) >= 0.5 {
            if let state = Self.readPersistedState(from: stateURL) {
                lastState = state
            }
            lastStateReadAt = now
        }

        guard let state = lastState, state.isOpen else {
            lastPlacement = nil
            wasPointerNearPet = false
            onPlacement?(nil)
            return
        }

        let pointerNearPet = lastPlacement?.mascotRect.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) == true
        let pointerDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
        let windowPollInterval = pointerNearPet || pointerDown ? 0.04 : 0.20
        guard now.timeIntervalSince(lastWindowPollAt) >= windowPollInterval else {
            if pointerDown || pointerNearPet != wasPointerNearPet {
                onPlacement?(lastPlacement)
            }
            wasPointerNearPet = pointerNearPet
            return
        }
        lastWindowPollAt = now

        guard let liveWindow = resolveLivePetWindow(near: state.windowRect) else {
            lastPlacement = nil
            wasPointerNearPet = false
            onPlacement?(nil)
            return
        }

        let cocoaWindow = Self.cocoaRect(fromQuartzRect: liveWindow.rect)
        let offset = state.mascotOffset
        let mascot = CGRect(
            x: cocoaWindow.minX + offset.minX,
            y: cocoaWindow.maxY - offset.maxY,
            width: offset.width,
            height: offset.height
        )
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(mascot) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? cocoaWindow
        let placement = PetPlacement(mascotRect: mascot, screenFrame: screen)
        let placementChanged = placement != lastPlacement
        lastPlacement = placement
        wasPointerNearPet = placement.mascotRect.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation)
        if placementChanged || wasPointerNearPet || pointerDown {
            onPlacement?(placement)
        }
    }

    nonisolated static func readPersistedState(from url: URL) -> PersistedPetState? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let open = root["electron-avatar-overlay-open"] as? Bool,
              let bounds = root["electron-avatar-overlay-bounds"] as? [String: Any],
              let mascot = bounds["mascot"] as? [String: Any],
              let x = number(bounds["x"]), let y = number(bounds["y"]),
              let width = number(bounds["width"]), let height = number(bounds["height"]),
              let left = number(mascot["left"]), let top = number(mascot["top"]),
              let mascotWidth = number(mascot["width"]), let mascotHeight = number(mascot["height"]) else {
            return nil
        }
        return PersistedPetState(
            isOpen: open,
            windowRect: CGRect(x: x, y: y, width: width, height: height),
            mascotOffset: CGRect(x: left, y: top, width: mascotWidth, height: mascotHeight)
        )
    }

    nonisolated private static func number(_ value: Any?) -> CGFloat? {
        (value as? NSNumber).map { CGFloat($0.doubleValue) }
    }

    private func resolveLivePetWindow(near persisted: CGRect) -> LivePetWindow? {
        if let liveWindowID,
           let window = Self.windowInfo(for: liveWindowID, near: persisted) {
            return window
        }
        liveWindowID = nil
        guard let discovered = Self.findLivePetWindow(near: persisted) else { return nil }
        liveWindowID = discovered.id
        return discovered
    }

    private nonisolated static func windowInfo(for id: CGWindowID, near persisted: CGRect) -> LivePetWindow? {
        guard let windows = CGWindowListCopyWindowInfo([.optionIncludingWindow, .excludeDesktopElements], id)
                as? [[String: Any]] else { return nil }
        return windows.compactMap { livePetWindow(from: $0, near: persisted) }.first
    }

    nonisolated static func findLivePetWindow(near persisted: CGRect) -> LivePetWindow? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let candidates = windows.compactMap { livePetWindow(from: $0, near: persisted) }
        return candidates.min { lhs, rhs in
            hypot(lhs.rect.minX - persisted.minX, lhs.rect.minY - persisted.minY)
                < hypot(rhs.rect.minX - persisted.minX, rhs.rect.minY - persisted.minY)
        }
    }

    private nonisolated static func livePetWindow(
        from window: [String: Any],
        near persisted: CGRect
    ) -> LivePetWindow? {
        guard let ownerName = window[kCGWindowOwnerName as String] as? String,
              ownerName == "ChatGPT" || ownerName == "Codex",
              (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 3,
              let id = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        let sizeMatches = abs(rect.width - persisted.width) < 12 && abs(rect.height - persisted.height) < 12
        let knownSize = (abs(rect.width - 356) < 12 && abs(rect.height - 320) < 12)
            || (abs(rect.width - 384) < 12 && abs(rect.height - 400) < 12)
        return sizeMatches || knownSize ? LivePetWindow(id: id, rect: rect) : nil
    }

    static func cocoaRect(fromQuartzRect rect: CGRect) -> CGRect {
        guard let primaryScreenTop = NSScreen.screens.first?.frame.maxY else { return rect }
        return cocoaRect(fromQuartzRect: rect, primaryScreenTop: primaryScreenTop)
    }

    nonisolated static func cocoaRect(fromQuartzRect rect: CGRect, primaryScreenTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenTop - rect.maxY, width: rect.width, height: rect.height)
    }

}
