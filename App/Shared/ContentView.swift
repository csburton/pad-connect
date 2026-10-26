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

    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isLandscapePhone: Bool { verticalSizeClass == .compact }
    #else
    private let isLandscapePhone = false
    #endif

    private var showsPausedCard: Bool { model.isSessionActive && !pad.isBeltRunning }

    var body: some View {
        Group {
            if isLandscapePhone {
                landscapeLayout
            } else {
                portraitLayout
            }
        }
        .animation(.spring(duration: 0.4), value: showsPausedCard)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .confirmationDialog("Discard this walk?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard walk", role: .destructive) { model.discardSession() }
        } message: {
            Text("It won't be saved to Apple Health.")
        }
    }

    private var portraitLayout: some View {
        ScrollView {
            VStack(spacing: 28) {
                dial(size: 260)
                    .padding(.top, 12)
                controls
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// iPhone on its side: dial on the left, everything else on the right.
    private var landscapeLayout: some View {
        GeometryReader { geometry in
            HStack(spacing: 28) {
                dial(size: min(max(geometry.size.height - 40, 160), 250))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ScrollView {
                    VStack(spacing: 18) {
                        controls
                    }
                    .padding(.vertical, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: 420)
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var controls: some View {
        presetRow
        StartStopButton(isRunning: pad.isBeltRunning, height: isLandscapePhone ? 50 : 58) {
            taps += 1
            model.toggleBelt()
        }
        .keyboardShortcut(.space, modifiers: [])

        StatsRow(seconds: model.tracker.movingSeconds,
                 meters: model.tracker.distanceMeters,
                 kcal: model.tracker.activeKcal,
                 steps: model.tracker.steps)
            .padding(.top, 4)

        #if os(iOS)
        HeartRateBadge(watch: model.watch, padHeartRate: pad.heartRate)
        #endif

        if showsPausedCard {
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

    private func dial(size: CGFloat) -> some View {
        let buttonSize: CGFloat = size < 220 ? 46 : 56
        return ZStack(alignment: .bottom) {
            SpeedDial(speed: pad.speedKmh, maximum: pad.maximumSpeedKmh, size: size, lineWidth: size < 220 ? 11 : 14)

            HStack {
                RoundIconButton(systemImage: "minus", size: buttonSize) {
                    taps += 1
                    pad.adjustSpeed(by: -model.speedStepKmh)
                }
                .keyboardShortcut(.downArrow, modifiers: [])
                Spacer()
                RoundIconButton(systemImage: "plus", size: buttonSize) {
                    taps += 1
                    pad.adjustSpeed(by: model.speedStepKmh)
                }
                .keyboardShortcut(.upArrow, modifiers: [])
            }
            .frame(width: size + 40)
            .disabled(!pad.isBeltRunning)
            .opacity(pad.isBeltRunning ? 1 : 0.35)
        }
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

    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var compact: Bool { verticalSizeClass == .compact }
    #else
    private let compact = false
    #endif

    var body: some View {
        VStack(spacing: compact ? 14 : 28) {
            Spacer(minLength: compact ? 4 : 20)

            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 72 : 128, height: compact ? 72 : 128)
                .shadow(color: Theme.accent.opacity(0.35), radius: 18, y: 8)
                .phaseAnimator([1.0, 1.04]) { view, scale in
                    view.scaleEffect(isSearching ? scale : 1)
                } animation: { _ in .easeInOut(duration: 1.2) }

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


#if os(iOS)
/// Heart rate during the walk: from the Apple Watch while it's recording the
/// walk, otherwise from the pad's hand-grip sensors if it reports any.
struct HeartRateBadge: View {
    @ObservedObject var watch: WatchWorkoutLink
    let padHeartRate: Int?

    private var bpm: Int? { watch.heartRate.map { Int($0.rounded()) } ?? padHeartRate }

    var body: some View {
        if watch.isMirroring || bpm != nil {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.33))
                    .symbolEffect(.pulse, isActive: bpm != nil)
                Text(bpm.map { "\($0) BPM" } ?? "Recording on Apple Watch")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if watch.isMirroring {
                    Image(systemName: "applewatch")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .transition(.opacity)
        }
    }
}
#endif
