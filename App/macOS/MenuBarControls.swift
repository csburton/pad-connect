import PadKit
import SwiftUI

/// Compact controls in the Mac menu bar, so speed can be nudged without leaving your work.
struct MenuBarControls: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var pad: TreadmillController

    var body: some View {
        VStack(spacing: 16) {
            if case .connected(let name) = pad.state {
                HStack(spacing: 6) {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    Text(name).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                }

                ZStack(alignment: .bottom) {
                    SpeedDial(speed: pad.speedKmh, maximum: pad.maximumSpeedKmh, size: 150, lineWidth: 9)
                    HStack {
                        RoundIconButton(systemImage: "minus", size: 34) {
                            pad.adjustSpeed(by: -model.speedStepKmh)
                        }
                        Spacer()
                        RoundIconButton(systemImage: "plus", size: 34) {
                            pad.adjustSpeed(by: model.speedStepKmh)
                        }
                    }
                    .frame(width: 190)
                    .disabled(!pad.isBeltRunning)
                    .opacity(pad.isBeltRunning ? 1 : 0.35)
                }

                StartStopButton(isRunning: pad.isBeltRunning, height: 38) {
                    model.toggleBelt()
                }

                StatsRow(seconds: model.tracker.movingSeconds,
                         meters: model.tracker.distanceMeters,
                         kcal: model.tracker.activeKcal,
                         steps: model.tracker.steps,
                         compact: true)

                if model.isSessionActive && !pad.isBeltRunning {
                    HStack {
                        Button("Discard") { model.discardSession() }
                        Spacer()
                        Button("Finish & save") { model.finishSession() }
                            .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.small)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "figure.walk")
                        .font(.title)
                        .foregroundStyle(Theme.accentGradient)
                    Text("Walking pad not connected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Open PadConnect") { NSApp.activate() }
                        .controlSize(.small)
                }
                .padding(.vertical, 8)
            }

            Divider()
            Button("Quit PadConnect") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 280)
        .tint(Theme.accent)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var pad: TreadmillController

    var body: some View {
        if pad.isBeltRunning {
            Text("\(Format.speed(pad.speedKmh)) km/h")
        } else {
            Image(systemName: "figure.walk")
        }
    }
}
