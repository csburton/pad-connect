import SwiftUI

enum Theme {
    static let accent = Color(red: 0.18, green: 0.80, blue: 0.60)
    static let accentDeep = Color(red: 0.05, green: 0.62, blue: 0.55)
    static let stop = Color(red: 0.96, green: 0.36, blue: 0.36)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Soft accent wash behind every screen.
struct AmbientBackground: View {
    var active: Bool

    var body: some View {
        LinearGradient(colors: [Theme.accent.opacity(active ? 0.22 : 0.10), .clear],
                       startPoint: .top, endPoint: .center)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.8), value: active)
    }
}

/// The speed readout: an open ring that fills towards the pad's top speed.
struct SpeedDial: View {
    let speed: Double
    let maximum: Double
    var size: CGFloat = 260
    var lineWidth: CGFloat = 14

    private var fraction: Double {
        guard maximum > 0 else { return 0 }
        return min(max(speed / maximum, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.125, to: 0.875)
                .stroke(.quaternary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(90)) // trim starts at 3 o'clock; this puts the gap at the bottom
            Circle()
                .trim(from: 0.125, to: 0.125 + 0.75 * fraction)
                .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(90))
                .shadow(color: Theme.accent.opacity(fraction > 0 ? 0.45 : 0), radius: 10)

            VStack(spacing: 2) {
                Text(Format.speed(speed))
                    .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: speed))
                Text("KM/H")
                    .font(.system(size: max(size * 0.05, 10), weight: .semibold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.6), value: speed)
    }
}

struct RoundIconButton: View {
    let systemImage: String
    var size: CGFloat = 56
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.36, weight: .semibold))
                .frame(width: size, height: size)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.quaternary))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct StartStopButton: View {
    let isRunning: Bool
    var height: CGFloat = 58
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isRunning ? "Stop" : "Start", systemImage: isRunning ? "stop.fill" : "play.fill")
                .font(.system(size: height * 0.3, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: height)
                .foregroundStyle(isRunning ? Theme.stop : .white)
                .background {
                    if isRunning {
                        Capsule().fill(Theme.stop.opacity(0.14))
                    } else {
                        Capsule().fill(Theme.accentGradient)
                            .shadow(color: Theme.accent.opacity(0.35), radius: 12, y: 6)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: isRunning)
    }
}

struct StatsRow: View {
    let seconds: TimeInterval
    let meters: Double
    let kcal: Double
    let steps: Int?
    var compact = false

    var body: some View {
        HStack(spacing: 0) {
            stat(Format.duration(seconds), "TIME")
            divider
            stat(String(format: "%.2f", meters / 1000), "KM")
            divider
            stat(String(format: "%.0f", kcal), "KCAL")
            divider
            stat(steps.map(String.init) ?? "–", "STEPS")
        }
    }

    private var divider: some View {
        Rectangle().fill(.quaternary).frame(width: 1, height: compact ? 24 : 32)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(compact ? .body : .title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: compact ? 9 : 10, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
