import PadKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var pad: TreadmillController
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if case .connected = pad.state {
                    ControlView()
                } else {
                    ConnectView()
                }
            }
            .navigationTitle("PadConnect")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
}

// MARK: - Connect

struct ConnectView: View {
    @EnvironmentObject private var pad: TreadmillController

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    if case .connecting = pad.state { ProgressView() }
                    if case .scanning = pad.state { ProgressView() }
                    Text(statusText)
                }
            }
            if !pad.discovered.isEmpty {
                Section("Nearby pads") {
                    ForEach(pad.discovered) { found in
                        Button {
                            pad.connect(found.id)
                        } label: {
                            HStack {
                                Image(systemName: "figure.walk")
                                Text(found.name)
                                Spacer()
                                Text("\(found.rssi) dBm").foregroundStyle(.secondary).font(.caption)
                            }
                        }
                    }
                }
            }
            if let error = pad.lastError {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section {
                Button("Scan again") { pad.startScan() }
            } footer: {
                Text("Turn the pad on and close the Sports Show app, because the pad only accepts one connection at a time.")
            }
        }
        .onAppear { pad.startScan() }
        .onDisappear { pad.stopScan() }
    }

    private var statusText: String {
        switch pad.state {
        case .bluetoothOff: return "Bluetooth is off."
        case .unauthorized: return "PadConnect needs Bluetooth permission. Turn it on in Settings."
        case .idle: return "Not connected."
        case .scanning: return "Looking for your walking pad…"
        case .connecting(let name): return "Connecting to \(name)…"
        case .connected(let name): return "Connected to \(name)."
        }
    }
}

// MARK: - Control

struct ControlView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var pad: TreadmillController

    private var presets: [Double] {
        [2, 3, 4, 5, 6].filter { $0 >= pad.minimumSpeedKmh && $0 <= pad.maximumSpeedKmh }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                speedDial
                presetRow
                startStopButton
                StatsGrid(tracker: model.tracker)
                sessionControls
                messages
            }
            .padding()
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private var speedDial: some View {
        HStack(spacing: 24) {
            Button {
                pad.adjustSpeed(by: -model.speedStepKmh)
            } label: {
                Image(systemName: "minus.circle.fill").font(.system(size: 52))
            }
            .keyboardShortcut(.downArrow, modifiers: [])
            .disabled(!pad.isBeltRunning)

            VStack(spacing: 0) {
                Text(Format.speed(pad.speedKmh))
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("km/h").font(.headline).foregroundStyle(.secondary)
            }
            .frame(minWidth: 150)

            Button {
                pad.adjustSpeed(by: model.speedStepKmh)
            } label: {
                Image(systemName: "plus.circle.fill").font(.system(size: 52))
            }
            .keyboardShortcut(.upArrow, modifiers: [])
            .disabled(!pad.isBeltRunning)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }

    private var presetRow: some View {
        HStack {
            ForEach(presets, id: \.self) { speed in
                Button("\(Int(speed))") { pad.setSpeed(speed) }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var startStopButton: some View {
        Button {
            pad.isBeltRunning ? pad.stop() : pad.start()
        } label: {
            Label(pad.isBeltRunning ? "Stop" : "Start",
                  systemImage: pad.isBeltRunning ? "stop.fill" : "play.fill")
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(pad.isBeltRunning ? .red : .green)
        .keyboardShortcut(.space, modifiers: [])
    }

    @ViewBuilder
    private var sessionControls: some View {
        if model.isSessionActive {
            HStack {
                Button("Discard walk", role: .destructive) { model.discardSession() }
                    .buttonStyle(.bordered)
                Button("Finish walk") { model.finishSession() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var messages: some View {
        if let message = model.saveMessage {
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        if let error = pad.lastError {
            Text(error).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
        }
        if let kind = pad.protocolKind {
            Text("Connected using \(kind.rawValue)").font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

struct StatsGrid: View {
    let tracker: WorkoutTracker

    var body: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                Stat(title: "Time", value: Format.duration(tracker.movingSeconds))
                Stat(title: "Distance", value: Format.distance(tracker.distanceMeters))
            }
            GridRow {
                Stat(title: "Active kcal", value: String(format: "%.0f", tracker.activeKcal))
                Stat(title: "Steps", value: tracker.steps.map(String.init) ?? "–")
            }
        }
    }
}

struct Stat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Settings

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
                Section {
                    Picker("Speed button step", selection: $model.speedStepKmh) {
                        Text("0.1 km/h").tag(0.1)
                        Text("0.5 km/h").tag(0.5)
                        Text("1 km/h").tag(1.0)
                    }
                }
                Section {
                    Toggle("Use FitShow protocol", isOn: $preferFitShow)
                } footer: {
                    Text("PadConnect uses the standard FTMS protocol by default. Turn this on if speed changes don't work, then reconnect.")
                }
                if pad.rememberedPadID != nil {
                    Section {
                        Button("Forget this pad", role: .destructive) {
                            pad.disconnect(forget: true)
                            dismiss()
                        }
                    }
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
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 360)
        #endif
    }
}
