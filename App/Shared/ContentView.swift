import PadKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var pad: TreadmillController
    @State private var showingSettings = false

    private var isConnected: Bool {
        if case .connected = pad.state { return true }
        return false
    }

    var body: some View {
        ZStack {
            AmbientBackground(active: pad.isBeltRunning)

            VStack(spacing: 0) {
                header
                if isConnected {
                    ControlView()
                        .transition(.opacity)
                } else {
                    ConnectView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: isConnected)
        }
        .overlay(alignment: .top) { toast }
        .tint(Theme.accent)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(isConnected ? Theme.accent : Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(headerTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.body.weight(.medium))
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var headerTitle: String {
        switch pad.state {
        case .connected(let name): return name
        case .connecting: return "Connecting…"
        default: return "PadConnect"
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let message = model.saveMessage {
            Text(message)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
                .padding(.top, 56)
                .padding(.horizontal, 24)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { model.saveMessage = nil }
                }
        }
    }
}

// MARK: - Control

struct ControlView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var pad: TreadmillController
    @State private var taps = 0
    @State private var confirmingDiscard = false

    private var presets: [Double] {
        [2, 3, 4, 5, 6].filter { $0 >= pad.minimumSpeedKmh && $0 <= pad.maximumSpeedKmh }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                dial
                presetRow
                StartStopButton(isRunning: pad.isBeltRunning) {
                    taps += 1
                    model.toggleBelt()
                }
                .keyboardShortcut(.space, modifiers: [])

                StatsRow(seconds: model.tracker.movingSeconds,
                         meters: model.tracker.distanceMeters,
                         kcal: model.tracker.activeKcal,
                         steps: model.tracker.steps)
                    .padding(.top, 4)

                if model.isSessionActive && !pad.isBeltRunning {
                    pausedCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let error = pad.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.stop)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
            .animation(.spring(duration: 0.4), value: model.isSessionActive && !pad.isBeltRunning)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .confirmationDialog("Discard this walk?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard walk", role: .destructive) { model.discardSession() }
        } message: {
            Text("It won't be saved to Apple Health.")
        }
    }

    private var dial: some View {
        ZStack(alignment: .bottom) {
            SpeedDial(speed: pad.speedKmh, maximum: pad.maximumSpeedKmh)
                .frame(maxWidth: .infinity)

            HStack {
                RoundIconButton(systemImage: "minus") {
                    taps += 1
                    pad.adjustSpeed(by: -model.speedStepKmh)
                }
                .keyboardShortcut(.downArrow, modifiers: [])
                Spacer()
                RoundIconButton(systemImage: "plus") {
                    taps += 1
                    pad.adjustSpeed(by: model.speedStepKmh)
                }
                .keyboardShortcut(.upArrow, modifiers: [])
            }
            .frame(maxWidth: 300)
            .disabled(!pad.isBeltRunning)
            .opacity(pad.isBeltRunning ? 1 : 0.35)
        }
        .padding(.top, 12)
    }

    private var presetRow: some View {
        HStack(spacing: 10) {
            ForEach(presets, id: \.self) { speed in
                let selected = pad.isBeltRunning && abs(pad.speedKmh - speed) < 0.05
                Button {
                    taps += 1
                    pad.setSpeed(speed)
                } label: {
                    Text("\(Int(speed))")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background {
                            if selected {
                                Capsule().fill(Theme.accentGradient)
                            } else {
                                Capsule().fill(.quaternary.opacity(0.6))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: pad.speedKmh)
    }

    private var pausedCard: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("Walk paused")
                    .font(.headline)
                Text("Start again to carry on, or finish to save it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button("Discard") { confirmingDiscard = true }
                    .buttonStyle(.bordered)
                    .tint(Color.secondary)
                Button {
                    model.finishSession()
                } label: {
                    Text("Finish & save").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Connect

struct ConnectView: View {
    @EnvironmentObject private var pad: TreadmillController

    private var isSearching: Bool {
        switch pad.state {
        case .scanning, .connecting: return true
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 20)

            ZStack {
                Circle().fill(Theme.accent.opacity(0.10)).frame(width: 150, height: 150)
                Circle().fill(Theme.accent.opacity(0.14)).frame(width: 104, height: 104)
                Image(systemName: "figure.walk")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(Theme.accentGradient)
                    .symbolEffect(.pulse, isActive: isSearching)
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            if !pad.discovered.isEmpty {
                VStack(spacing: 10) {
                    ForEach(pad.discovered) { found in
                        Button {
                            pad.connect(found.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "figure.walk.motion")
                                    .foregroundStyle(Theme.accent)
                                Text(found.name).font(.body.weight(.medium))
                                Spacer()
                                Text("Connect")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                            .padding(.horizontal, 18)
                            .frame(minHeight: 54)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 24)
            }

            if let error = pad.lastError {
                Text(error).font(.footnote).foregroundStyle(Theme.stop).padding(.horizontal, 24)
            }

            Spacer()

            Button("Search again") { pad.startScan() }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .onAppear { pad.startScan() }
        .onDisappear { pad.stopScan() }
    }

    private var title: String {
        switch pad.state {
        case .bluetoothOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth access needed"
        case .connecting: return "Connecting"
        case .scanning where !pad.discovered.isEmpty, .idle where !pad.discovered.isEmpty: return "Pad found"
        default: return "Looking for your pad"
        }
    }

    private var subtitle: String {
        switch pad.state {
        case .bluetoothOff: return "Turn on Bluetooth to connect to your walking pad."
        case .unauthorized: return "Allow PadConnect to use Bluetooth in Settings."
        case .connecting(let name): return "Reaching \(name). Make sure it's switched on."
        default: return "Switch the pad on and close the Sports Show app. The pad only talks to one app at a time."
        }
    }
}
