import AppKit
import SwiftUI

private enum GlassPalette {
    static let accent = Color(nsColor: .controlAccentColor)
    static let connected = Color(nsColor: .systemGreen)
    static let syncing = Color(nsColor: .systemOrange)
    static let unavailable = Color(nsColor: .systemRed)
    static let track = Color.primary.opacity(0.10)
    static let hairline = Color.primary.opacity(0.09)
    static let fallbackWash = Color.white.opacity(0.055)
}

enum OverlayLayout {
    static let width: CGFloat = 224
    static let twoWindowHeight: CGFloat = 174
    static let oneWindowHeight: CGFloat = 116

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
        glassSurface
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            .padding(6)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header

            Spacer().frame(height: 10)

            UsageRow(window: windows.first, now: model.now)

            if windows.count > 1 {
                Spacer().frame(height: 7)

                Divider()
                    .overlay(GlassPalette.hairline)

                Spacer().frame(height: 7)

                UsageRow(window: windows[1], now: model.now)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(width: panelSize.width - 12, height: panelSize.height - 12)
    }

    @ViewBuilder
    private var glassSurface: some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous)
                )
        } else {
            content
                .background {
                    ZStack {
                        MacGlassView(material: .popover, blendingMode: .behindWindow)
                        GlassPalette.fallbackWash
                        LinearGradient(
                            colors: [Color.white.opacity(0.09), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.24), Color.primary.opacity(0.07)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.6
                        )
                }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(GlassPalette.accent)
                .frame(width: 23, height: 23)
                .background(GlassPalette.accent.opacity(0.13), in: Circle())

            Text("Codex Energy")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 4.5, height: 4.5)
                Text(statusLabel)
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(0.35)
            }
            .foregroundStyle(statusColor)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Color.primary.opacity(0.065), in: Capsule())
        }
    }

    private var statusColor: Color {
        switch model.connectionState {
        case .connected:
            return GlassPalette.connected
        case .connecting:
            return GlassPalette.syncing
        case .unavailable:
            return GlassPalette.unavailable
        }
    }

    private var statusLabel: String {
        switch model.connectionState {
        case .connected: return "LIVE"
        case .connecting: return "SYNC"
        case .unavailable: return "OFFLINE"
        }
    }
}

private struct UsageRow: View {
    let window: UsageWindow?
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayLabel)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if let window {
                    HStack(alignment: .firstTextBaseline, spacing: 2.5) {
                        Text("\(window.remainingPercent)%")
                            .font(.system(size: 17, weight: .semibold))
                            .monospacedDigit()
                        Text("left")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                } else {
                    Text("—")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer().frame(height: 5)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(GlassPalette.track)
                    if let window, window.remainingPercent > 0 {
                        Capsule()
                            .fill(energyColor(for: window.remainingPercent))
                            .frame(width: max(5, proxy.size.width * CGFloat(window.remainingPercent) / 100))
                    }
                }
            }
            .frame(height: 5)
            .animation(.smooth(duration: 0.45), value: window?.remainingPercent)

            Spacer().frame(height: 5)

            HStack(spacing: 4.5) {
                Image(systemName: "clock")
                    .font(.system(size: 8.5, weight: .medium))
                Text(window?.resetDescription(relativeTo: now) ?? "Usage unavailable")
                    .font(.system(size: 9.5, weight: .medium))
                    .monospacedDigit()
                Spacer()
            }
            .foregroundStyle(.secondary)
        }
    }

    private var displayLabel: String {
        window?.label ?? "Usage Limit"
    }

    private func energyColor(for remainingPercent: Int) -> Color {
        switch remainingPercent {
        case ...15: return Color(nsColor: .systemRed)
        case ...30: return Color(nsColor: .systemOrange)
        default: return GlassPalette.accent
        }
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
