import AppKit
import SwiftUI

private enum GlassPalette {
    static let appleIvory = Color(red: 1.0, green: 254.0 / 255.0, blue: 201.0 / 255.0)
    static let primary = appleIvory.opacity(0.96)
    static let secondary = appleIvory.opacity(0.72)
    static let tertiary = appleIvory.opacity(0.46)
    static let track = appleIvory.opacity(0.13)
    static let hairline = appleIvory.opacity(0.11)
}

enum OverlayLayout {
    static let width: CGFloat = 207
    static let twoWindowHeight: CGFloat = 178
    static let oneWindowHeight: CGFloat = 124

    static func panelSize(windowCount: Int) -> CGSize {
        CGSize(width: width, height: windowCount > 1 ? twoWindowHeight : oneWindowHeight)
    }
}

struct OverlayView: View {
    @ObservedObject var model: AppModel

    private var windows: [UsageWindow] {
        [model.primary, model.secondary].compactMap { $0 }
    }

    private var panelSize: CGSize {
        OverlayLayout.panelSize(windowCount: windows.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer().frame(height: 9)

            UsageRow(window: windows.first, now: model.now)

            if windows.count > 1 {
                Spacer().frame(height: 8)

                Divider()
                    .overlay(GlassPalette.hairline)

                Spacer().frame(height: 8)

                UsageRow(window: windows[1], now: model.now)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(width: panelSize.width - 12, height: panelSize.height - 12)
        .background {
            ZStack {
                MacGlassView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.15)
                LinearGradient(
                    colors: [GlassPalette.appleIvory.opacity(0.045), .clear, .black.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [GlassPalette.appleIvory.opacity(0.18), GlassPalette.appleIvory.opacity(0.045)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.6
                )
        }
        .shadow(color: .black.opacity(0.20), radius: 16, y: 7)
        .padding(6)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "bolt.horizontal.fill")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(GlassPalette.primary)
                .frame(width: 21, height: 21)
                .background(GlassPalette.appleIvory.opacity(0.10), in: Circle())

            Text("Codex Usage")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(GlassPalette.primary)

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 4.5, height: 4.5)
                Text(statusLabel)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .tracking(0.35)
            }
            .foregroundStyle(statusColor)
            .padding(.horizontal, 7)
            .frame(height: 21)
            .background(GlassPalette.appleIvory.opacity(0.075), in: Capsule())
        }
    }

    private var statusColor: Color {
        if case .connected = model.connectionState {
            return GlassPalette.secondary
        }
        return GlassPalette.tertiary
    }

    private var statusLabel: String {
        if case .connected = model.connectionState { return "LIVE" }
        return "SYNCING"
    }
}

private struct UsageRow: View {
    let window: UsageWindow?
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(GlassPalette.secondary)

                Spacer()

                if let window {
                    HStack(alignment: .firstTextBaseline, spacing: 2.5) {
                        Text("\(window.remainingPercent)%")
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("left")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(GlassPalette.primary)
                } else {
                    Text("—")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(GlassPalette.tertiary)
                }
            }

            Spacer().frame(height: 7)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(GlassPalette.track)
                    if let window {
                        Capsule()
                            .fill(GlassPalette.primary)
                            .frame(width: max(4, proxy.size.width * CGFloat(window.remainingPercent) / 100))
                    }
                }
            }
            .frame(height: 4)

            Spacer().frame(height: 6)

            HStack(spacing: 4.5) {
                Image(systemName: "clock")
                    .font(.system(size: 8.5, weight: .semibold))
                Text(window?.resetDescription(relativeTo: now) ?? "Usage unavailable")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Spacer()
            }
            .foregroundStyle(GlassPalette.tertiary)
        }
    }

    private var displayLabel: String {
        window?.label ?? "Usage Limit"
    }

}

private struct MacGlassView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
    }
}
