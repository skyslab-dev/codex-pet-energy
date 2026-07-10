import AppKit
import SwiftUI

private enum GlassPalette {
    // Sampled from the Apple reference: RGB(255, 254, 201).
    // All hierarchy levels share this hue and vary only in opacity.
    static let appleIvory = Color(red: 1.0, green: 254.0 / 255.0, blue: 201.0 / 255.0)
    static let primary = appleIvory
    static let secondary = appleIvory.opacity(0.76)
    static let tertiary = appleIvory.opacity(0.42)
}

struct OverlayView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 5) {
            header

            UsageRow(window: model.primary, now: model.now)

            Divider()
                .overlay(GlassPalette.primary.opacity(0.12))

            UsageRow(window: model.secondary, now: model.now)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: 195, height: 166)
        .background {
            ZStack {
                MacGlassView(material: .underWindowBackground, blendingMode: .behindWindow)
                Color.black.opacity(0.17)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(GlassPalette.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 13, y: 5)
        .padding(6)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.horizontal.fill")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(GlassPalette.primary)
                .frame(width: 14)

            Text("Codex usage")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(GlassPalette.primary)

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                Text(statusLabel)
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .foregroundStyle(statusColor)
        }
        .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
    }

    private var statusColor: Color {
        if case .connected = model.connectionState {
            return GlassPalette.secondary
        }
        return GlassPalette.tertiary
    }

    private var statusLabel: String {
        if case .connected = model.connectionState { return "Live" }
        return "Syncing"
    }
}

private struct UsageRow: View {
    let window: UsageWindow?
    let now: Date

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayLabel)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(GlassPalette.secondary)

                Spacer()

                if let window {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(window.remainingPercent)%")
                            .font(.system(size: 15, weight: .bold))
                            .monospacedDigit()
                        Text("left")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .foregroundStyle(color(for: window.remainingPercent))
                } else {
                    Text("—")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GlassPalette.tertiary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(GlassPalette.primary.opacity(0.15))
                    if let window {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [color(for: window.remainingPercent).opacity(0.78), color(for: window.remainingPercent)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(6, proxy.size.width * CGFloat(window.remainingPercent) / 100))
                            .shadow(color: GlassPalette.primary.opacity(0.12), radius: 3)
                    }
                }
            }
            .frame(height: 5)

            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 8.5, weight: .medium))
                Text(window?.resetDescription(relativeTo: now) ?? "Usage unavailable")
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                Spacer()
            }
            .foregroundStyle(GlassPalette.tertiary)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .shadow(color: .black.opacity(0.10), radius: 1, y: 0.5)
    }

    private var displayLabel: String {
        switch window?.label {
        case "5-HOUR LIMIT": return "5-hour limit"
        case "WEEKLY LIMIT": return "Weekly limit"
        default: return "Usage limit"
        }
    }

    private func color(for _: Int) -> Color {
        return GlassPalette.primary
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
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
    }
}
