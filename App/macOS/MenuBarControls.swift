import PadKit
import SwiftUI

/// Compact controls in the Mac menu bar, so speed can be nudged without leaving your work.
struct MenuBarControls: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var pad: TreadmillController

    var body: some View {
        VStack(spacing: 12) {
            if case .connected(let name) = pad.state {
                Text(name).font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Button { pad.adjustSpeed(by: -model.speedStepKmh) } label: {
                        Image(systemName: "minus.circle.fill").font(.title)
                    }
                    .disabled(!pad.isBeltRunning)

                    Text("\(Format.speed(pad.speedKmh)) km/h")
                        .font(.title2.bold()).monospacedDigit()
                        .frame(minWidth: 110)

                    Button { pad.adjustSpeed(by: model.speedStepKmh) } label: {
                        Image(systemName: "plus.circle.fill").font(.title)
                    }
                    .disabled(!pad.isBeltRunning)
                }
                .buttonStyle(.plain)

                Button {
                    pad.isBeltRunning ? pad.stop() : pad.start()
                } label: {
                    Label(pad.isBeltRunning ? "Stop" : "Start", systemImage: pad.isBeltRunning ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(pad.isBeltRunning ? .red : .green)

                HStack {
                    Text(Format.duration(model.tracker.movingSeconds))
                    Spacer()
                    Text(Format.distance(model.tracker.distanceMeters))
                }
                .font(.callout).monospacedDigit().foregroundStyle(.secondary)

                if model.isSessionActive {
                    Button("Finish walk") { model.finishSession() }
                }
            } else {
                Text("Walking pad not connected").foregroundStyle(.secondary)
                Button("Open PadConnect") { NSApp.activate() }
            }

            Divider()
            Button("Quit PadConnect") { NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 260)
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
