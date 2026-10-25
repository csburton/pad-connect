import PadKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var pad: TreadmillController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("preferFitShow") private var preferFitShow = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $model.bodyMassKg, in: 30...200, step: 1) {
                        LabeledContent("Body weight", value: "\(Int(model.bodyMassKg)) kg")
                    }
                } footer: {
                    Text("Used to estimate active calories.")
                }

                Section("Speed buttons") {
                    Picker("Step", selection: $model.speedStepKmh) {
                        Text("0.1").tag(0.1)
                        Text("0.5").tag(0.5)
                        Text("1.0").tag(1.0)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    if case .connected(let name) = pad.state {
                        LabeledContent("Pad", value: name)
                        if let kind = pad.protocolKind {
                            LabeledContent("Protocol", value: kind.rawValue)
                        }
                        LabeledContent("Speed range",
                                       value: "\(Format.speed(pad.minimumSpeedKmh))–\(Format.speed(pad.maximumSpeedKmh)) km/h")
                    }
                    Toggle("Use FitShow protocol", isOn: $preferFitShow)
                    if pad.rememberedPadID != nil {
                        Button("Forget this pad", role: .destructive) {
                            pad.disconnect(forget: true)
                            dismiss()
                        }
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text("PadConnect uses the standard FTMS protocol by default. If speed changes don't work, turn on FitShow and reconnect.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 420)
        #endif
    }
}
