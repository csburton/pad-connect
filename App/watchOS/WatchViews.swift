import PadKit
import SwiftUI

private let accent = Color(red: 0.18, green: 0.80, blue: 0.60)
private let heartRed = Color(red: 1.0, green: 0.27, blue: 0.33)

struct WatchRootView: View {
    @EnvironmentObject private var workout: WorkoutManager

    var body: some View {
        switch workout.phase {
        case .idle:
            IdleView()
        case .running:
            TabView {
                MetricsView()
                ControlsView()
            }
            .tabViewStyle(.verticalPage)
        case .saving, .saved, .discarded, .failed:
            SummaryView()
        }
    }
}

struct IdleView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
            Text("PadConnect")
                .font(.headline)
            Text("Start the pad from your iPhone and your walk will appear here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct MetricsView: View {
    @EnvironmentObject private var workout: WorkoutManager

    var body: some View {
        TimelineView(.periodic(from: workout.startDate ?? .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.format(workout.elapsedTime(at: context.date)))
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(accent)
                    .monospacedDigit()

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", workout.speedKmh))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: workout.speedKmh))
                    Text("KM/H").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "heart.fill").foregroundStyle(heartRed)
                        .symbolEffect(.pulse, isActive: workout.heartRate != nil)
                    Text(workout.heartRate.map { String(Int($0)) } ?? "--")
                        .monospacedDigit()
                    Text("BPM").font(.caption2).foregroundStyle(.secondary)
                }
                .font(.system(.title3, design: .rounded).weight(.medium))

                HStack(spacing: 12) {
                    Text(String(format: "%.2f KM", workout.distanceMeters / 1000))
                    Text(String(format: "%.0f KCAL", workout.activeKcal))
                }
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()

                if !workout.isConnectedToPhone {
                    Label("iPhone not connected", systemImage: "iphone.slash")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

struct ControlsView: View {
    @EnvironmentObject private var workout: WorkoutManager
    @State private var confirmingDiscard = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { workout.send(.speedDown) } label: {
                    Image(systemName: "minus").font(.title3.weight(.semibold))
                }
                .disabled(!workout.isBeltRunning)

                Text(String(format: "%.1f", workout.speedKmh))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 44)

                Button { workout.send(.speedUp) } label: {
                    Image(systemName: "plus").font(.title3.weight(.semibold))
                }
                .disabled(!workout.isBeltRunning)
            }

            Button { workout.send(.toggleBelt) } label: {
                Label(workout.isBeltRunning ? "Stop belt" : "Start belt",
                      systemImage: workout.isBeltRunning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(workout.isBeltRunning ? heartRed : accent)

            HStack(spacing: 8) {
                Button(role: .destructive) { confirmingDiscard = true } label: {
                    Image(systemName: "xmark")
                }
                Button { workout.end(save: true) } label: {
                    Text("Finish").frame(maxWidth: .infinity)
                }
                .tint(accent)
            }
        }
        .confirmationDialog("Discard this walk?", isPresented: $confirmingDiscard) {
            Button("Discard", role: .destructive) { workout.end(save: false) }
        }
    }
}

struct SummaryView: View {
    @EnvironmentObject private var workout: WorkoutManager

    var body: some View {
        VStack(spacing: 10) {
            switch workout.phase {
            case .saving:
                ProgressView()
                Text("Saving…")
            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(accent)
                Text("Walk saved").font(.headline)
                Text(String(format: "%.2f km · %.0f kcal", workout.distanceMeters / 1000, workout.activeKcal))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .discarded:
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Walk discarded").font(.headline)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text(message).font(.footnote).multilineTextAlignment(.center)
            default:
                EmptyView()
            }
            if workout.phase != .saving {
                Button("Done") { workout.dismissSummary() }
            }
        }
        .padding()
    }
}
