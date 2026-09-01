import SwiftUI

/// Routes on the recorder's phase, and nothing else.
///
/// The watch has exactly three screens because it does exactly three things: wait for a fix,
/// record, and report. Anything that would need a fourth belongs on the phone, where there is
/// room to be wrong about it in public.
struct RootView: View {
    @Environment(SessionRecorder.self) private var recorder

    var body: some View {
        Group {
            switch recorder.phase {
            case .idle, .starting:
                StartView()
            case .recording, .paused:
                RecordingView()
            case .saving:
                SavingView()
            case .finished:
                SummaryView()
            case .failed(let message):
                FailureView(message: message)
            }
        }
        // The app paints its own ground rather than taking the system's: a wingfoiler reads
        // this in full Garda sun through polarised sunglasses, and the brand navy under a
        // near-white number is the highest contrast the palette has.
        .containerBackground(Brand.navy.gradient, for: .navigation)
    }
}

/// The half-second between STOP and the summary, said out loud rather than left blank —
/// finishing a workout writes to HealthKit and assembles a file, and a screen that went
/// briefly dark there would read as a crash.
struct SavingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(Brand.green)
            Text("Saving session")
                .font(.headline)
                .foregroundStyle(Brand.paper)
        }
    }
}

struct FailureView: View {
    @Environment(SessionRecorder.self) private var recorder
    let message: String

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Brand.paper)
                Button("Back") { recorder.dismissSummary() }
                    .buttonStyle(.bordered)
                    .tint(Brand.cyan)
            }
            .padding(.vertical, 8)
        }
    }
}
