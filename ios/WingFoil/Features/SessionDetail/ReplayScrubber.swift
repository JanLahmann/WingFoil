import SwiftUI
import WingFoilKit

/// Replay control for one session: a scrub bar, a play button, and a live readout of the
/// instant under the playhead.
///
/// Everything it drives is already in memory — this is pure presentation over
/// `SessionDetail.timeline`, no engine call and no re-parse. The playhead is a plain
/// `Double?` binding shared with the chart and the map, which is what makes those two
/// linked: whoever moves it, all three follow.
struct ReplayScrubber: View {
    let detail: SessionDetail
    @Binding var playhead: Double?

    @State private var isPlaying = false
    @State private var rate = ReplayRate.x30

    /// Playback speeds. 30× turns a two-hour session into four minutes, which is about the
    /// pace at which a jibe is still recognisable.
    enum ReplayRate: Double, CaseIterable, Identifiable {
        case x10 = 10, x30 = 30, x60 = 60

        var id: Double { rawValue }
        var label: String { "\(Int(rawValue))×" }
    }

    /// Playhead ticks per second of wall clock. 20 is smooth to the eye and cheap enough
    /// that a scrubbing session does not warm the phone.
    private static let ticksPerSecond = 20.0

    private var range: ClosedRange<Double>? { detail.timeRange }

    private var moment: SessionDetail.TimelinePoint? {
        guard let playhead else { return nil }
        return detail.moment(at: playhead)
    }

    var body: some View {
        if let range {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("Replay").font(.headline)
                    Spacer()
                    if playhead != nil {
                        Button("Clear") { stop(); playhead = nil }
                            .font(.caption)
                    }
                }

                readout(range: range)
                controls(range: range)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
            // Playback advances on a timer while `isPlaying`; flipping the flag cancels
            // the task, so there is never more than one loop running.
            .task(id: isPlaying) {
                guard isPlaying else { return }
                let step = rate.rawValue / Self.ticksPerSecond
                let nanos = UInt64(1_000_000_000 / Self.ticksPerSecond)
                while !Task.isCancelled && isPlaying {
                    try? await Task.sleep(nanoseconds: nanos)
                    guard !Task.isCancelled else { return }
                    let next = (playhead ?? range.lowerBound) + step
                    if next >= range.upperBound {
                        playhead = range.upperBound
                        isPlaying = false
                        return
                    }
                    playhead = next
                }
            }
        }
    }

    // MARK: - Readout

    @ViewBuilder
    private func readout(range: ClosedRange<Double>) -> some View {
        let moment = self.moment
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            field(Fmt.clock((playhead ?? range.lowerBound) - range.lowerBound), "elapsed")
            field(moment.map { String(format: "%.1f", $0.kn) } ?? "—", "kn")
            if detail.hasHeartRate {
                field(moment?.hr.map { "\(Int($0.rounded()))" } ?? "—", "bpm")
            }
            Spacer(minLength: 0)
            phase(moment)
        }
        .font(.title3.weight(.semibold).monospacedDigit())
    }

    private func field(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
            Text(unit).font(.caption2.weight(.regular)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func phase(_ moment: SessionDetail.TimelinePoint?) -> some View {
        if let moment {
            Text(moment.flying ? "flying" : "off foil")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background((moment.flying ? Color.teal : Color.secondary).opacity(0.18),
                            in: .capsule)
                .foregroundStyle(moment.flying ? Color.teal : Color.secondary)
        }
    }

    // MARK: - Controls

    private func controls(range: ClosedRange<Double>) -> some View {
        HStack(spacing: 12) {
            Button {
                if isPlaying {
                    isPlaying = false
                } else {
                    // Restarting from the end would play nothing; rewind first.
                    if playhead == nil || (playhead ?? 0) >= range.upperBound - 0.5 {
                        playhead = range.lowerBound
                    }
                    isPlaying = true
                }
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause replay" : "Play replay")

            Slider(value: Binding(get: { playhead ?? range.lowerBound },
                                  set: { playhead = $0 }),
                   in: range)
                .tint(.accentColor)
                .accessibilityLabel("Replay position")

            Picker("Speed", selection: $rate) {
                ForEach(ReplayRate.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
        }
    }

    private func stop() { isPlaying = false }
}
