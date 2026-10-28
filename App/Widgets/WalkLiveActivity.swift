import ActivityKit
import SwiftUI
import WidgetKit

private let accent = Color(red: 0.18, green: 0.80, blue: 0.60)
private let heartRed = Color(red: 0.96, green: 0.36, blue: 0.36)

/// The active walk on the Lock Screen and in the Dynamic Island.
struct WalkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(accent)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Metric(value: state.speedText, unit: "KM/H")
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let bpm = state.heartRate {
                        Metric(value: "\(bpm)", unit: "BPM", tint: heartRed)
                            .padding(.trailing, 4)
                    } else {
                        Metric(value: state.distanceText, unit: "KM")
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    WalkClock(state: state)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(state.isFinished ? "Walk finished" : (state.isBeltRunning ? "Walking" : "Belt stopped"),
                              systemImage: "figure.walk")
                            .foregroundStyle(state.isBeltRunning ? accent : .secondary)
                        Spacer()
                        if state.heartRate != nil {
                            Text("\(state.distanceText) km")
                                .monospacedDigit()
                        }
                    }
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "figure.walk")
                    .foregroundStyle(accent)
            } compactTrailing: {
                WalkClock(state: state)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .frame(maxWidth: 52)
                    .foregroundStyle(accent)
            } minimal: {
                Image(systemName: "figure.walk")
                    .foregroundStyle(accent)
            }
            .keylineTint(accent)
        }
    }
}

/// Walking time. Ticks by itself while the belt runs, and holds still when it stops.
private struct WalkClock: View {
    let state: WalkActivityAttributes.ContentState

    var body: some View {
        Group {
            if let start = state.clockStart, !state.isFinished {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
            } else {
                Text(state.durationText)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.center)
    }
}

private struct Metric: View {
    let value: String
    let unit: String
    var tint: Color = .primary

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(unit)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LockScreenView: View {
    let state: WalkActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(state.isFinished ? "Walk finished" : "PadConnect", systemImage: "figure.walk")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(accent)
                Spacer()
                if !state.isFinished && !state.isBeltRunning {
                    Text("Belt stopped")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .lastTextBaseline) {
                WalkClock(state: state)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !state.isFinished {
                    Metric(value: state.speedText, unit: "KM/H")
                }
                Metric(value: state.distanceText, unit: "KM")
                    .padding(.leading, 12)
                if let bpm = state.heartRate {
                    Metric(value: "\(bpm)", unit: "BPM", tint: heartRed)
                        .padding(.leading, 12)
                }
            }
        }
        .padding(16)
        // The tint behind it is dark in both light and dark mode.
        .environment(\.colorScheme, .dark)
    }
}
