import AppKit
import Combine
import SwiftUI

private struct OverlayContentState: Equatable {
    let windowCount: Int
    let showsWeeklyActivity: Bool
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayPanelController {
    private let panel: OverlayPanel
    private let model: AppModel
    private let tracker = PetTracker()
    private var usageWindowSubscription: AnyCancellable?
    private var isPresented = false
    private var isDraggingPet = false
    private var wasLeftButtonDown = false

    init(model: AppModel) {
        self.model = model
        let initialWindowCount = [model.primary, model.secondary].compactMap { $0 }.count
        let panelSize = OverlayLayout.panelSize(
            windowCount: initialWindowCount,
            showsWeeklyActivity: model.weeklyTokenActivity != nil
        )
        panel = OverlayPanel(
            contentRect: CGRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        let hostingView = NSHostingView(rootView: OverlayView(model: model))
        hostingView.frame = CGRect(origin: .zero, size: panelSize)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        panel.setContentSize(panelSize)

        usageWindowSubscription = model.$primary
            .combineLatest(model.$secondary, model.$tokenUsageProfile)
            .map { primary, secondary, profile in
                let windows = [primary, secondary].compactMap { $0 }
                let hasWeeklyWindow = windows.contains {
                    $0.windowDurationMinutes == 10_080 && $0.resetsAt != nil
                }
                let showsWeeklyActivity = profile != nil && hasWeeklyWindow
                return OverlayContentState(
                    windowCount: windows.count,
                    showsWeeklyActivity: showsWeeklyActivity
                )
            }
            .removeDuplicates()
            .sink { [weak self] state in
                self?.updatePanelSize(
                    for: state.windowCount,
                    showsWeeklyActivity: state.showsWeeklyActivity
                )
            }

        tracker.onPlacement = { [weak self] placement in
            self?.apply(placement)
        }
    }

    func start() {
        tracker.start()
    }

    func stop() {
        tracker.stop()
        isDraggingPet = false
        dismiss()
    }

    func setEnabled(_ enabled: Bool) {
        model.overlayEnabled = enabled
        if !enabled {
            isDraggingPet = false
            wasLeftButtonDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
            dismiss()
        }
    }

    private func apply(_ placement: PetPlacement?) {
        model.petVisible = placement != nil
        guard model.overlayEnabled, let placement else {
            dismiss()
            return
        }

        // Hovering presents the panel. Once a drag begins on the Pet, keep the
        // panel alive until mouse-up even if the moving window briefly lags
        // behind the pointer by a few frames.
        let petHoverRegion = placement.mascotRect.insetBy(dx: -5, dy: -5)
        let isHoveringPet = petHoverRegion.contains(NSEvent.mouseLocation)
        let isLeftButtonDown = CGEventSource.buttonState(.combinedSessionState, button: .left)

        if isLeftButtonDown && !wasLeftButtonDown && isHoveringPet {
            isDraggingPet = true
        }
        if !isLeftButtonDown && wasLeftButtonDown {
            isDraggingPet = false
        }
        wasLeftButtonDown = isLeftButtonDown
        isPresented = isHoveringPet || isDraggingPet

        if !isPresented {
            dismiss()
            return
        }

        let frame = OverlayPositioner.frame(for: panel.frame.size, beside: placement)
        if !panel.frame.isApproximatelyEqual(to: frame) {
            panel.setFrame(frame, display: true)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func dismiss() {
        isPresented = false
        if !CGEventSource.buttonState(.combinedSessionState, button: .left) {
            isDraggingPet = false
        }
        if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    private func updatePanelSize(for windowCount: Int, showsWeeklyActivity: Bool) {
        let size = OverlayLayout.panelSize(
            windowCount: windowCount,
            showsWeeklyActivity: showsWeeklyActivity
        )
        guard panel.frame.size != size else { return }
        panel.setContentSize(size)
    }
}

private extension CGRect {
    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
