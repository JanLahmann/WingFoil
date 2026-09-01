import SwiftUI

/// After STOP: three numbers and where the rest of them are.
///
/// **Three numbers, deliberately.** The watch knows duration, distance and top speed for
/// certain, because it measured them. It does not know how many flights there were, how long
/// the longest one was, or what the best 2-second window came to — those come out of the
/// analysis engine on the phone, from the same accelerometer and Doppler streams this screen
/// has just finished writing. Printing a guess at them here would mean two answers to every
/// question, and the rider would have no way to tell which one the app meant.
///
/// So the last line is not an apology for a thin screen. It is the shape of the product: the
/// watch records, the phone analyses, and the handoff is instant and account-free — no cable,
/// no Connect, no cloud, no waiting for a sync that happens on somebody else's schedule.
struct SummaryView: View {
    @Environment(SessionRecorder.self) private var recorder

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Session saved")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Brand.green)

                if let summary = recorder.summary {
                    Row(label: "Time", value: WatchFormat.duration(summary.durationS))
                    Row(label: "Distance", value: WatchFormat.distance(summary.distanceM))
                    Row(label: "Top speed", value: "\(WatchFormat.speed(summary.maxSpeedMps)) kn")

                    Divider().overlay(Brand.paper.opacity(0.2))

                    Text(summary.queuedForTransfer
                         ? "Open CleanJibe on your iPhone to analyze."
                         : "Saved on the watch. It will reach your iPhone when they are together.")
                        .font(.caption2)
                        .foregroundStyle(Brand.cyan)

                    // Not decoration: it is the one place a rider can confirm the wrist
                    // actually captured the accelerometer, which is what decides whether the
                    // phone can show pump strokes and takeoff effort at all.
                    Text("\(summary.trackCount) fixes · \(summary.accelCount) accel")
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.paper.opacity(0.45))
                }

                Button("Done") { recorder.dismissSummary() }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.green)
                    .foregroundStyle(Brand.navy)
                    .padding(.top, 2)
            }
            .padding(.vertical, 6)
        }
    }
}

private struct Row: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(Brand.paper.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Brand.paper)
        }
    }
}
