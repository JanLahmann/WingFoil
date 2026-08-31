import SwiftUI
import WingFoilKit

/// Replay control for one session: a scrub bar, a play button, and a live readout of the
/// instant under the playhead.
///
/// Everything it drives is already in memory — this is pure presentation over
/// `SessionDetail.timeline`, no engine call and no re-parse. The playhead is a plain
/// `Double?` binding shared with the chart and the map, which is what makes those two
/// linked: whoever moves it, all three follow.
///
/// **The beat bar.** A two-hour session is 300 pt of undifferentiated grey, and scrubbing
/// it blind to find the jibe you remember is the whole reason nobody used this control. The
/// strip above the slider marks the instants worth watching — every takeoff, every counted
/// jibe in its outcome's colour, the 2 s peak, the longest flight — and the two skip
/// buttons walk them. Which instants those are is `ReplayBeats`, in the kit, because it is
/// a statement about the session rather than about this view.
///
/// **The record button.** The one thing on this card that leaves the phone. It is here, on
/// the replay's own controls, rather than in the share sheet beside the card and the FIT: a
/// clip does not *exist* until the replay has been played, so the button that makes one
/// belongs next to the speeds it will be played at, in the place a rider is already thinking
/// about playback. (The share sheet stays what it is — a chooser over things that are already
/// finished.)
struct ReplayScrubber: View {
    let detail: SessionDetail
    @Binding var playhead: Double?
    /// The replay's commentary track, already filtered by the rider's toggle upstream — the
    /// same list the map is drawing captions from. Passed in rather than derived so the
    /// cinema replay's captions, its slow-motion beats and the map's bubbles are one script.
    var milestones: [ReplayMilestone] = []

    /// Only for the commentary switch — the one control on this row that is a *preference*
    /// rather than a position, and therefore belongs to the rider and not to this session.
    @Environment(SessionStore.self) private var store

    @State private var isPlaying = false
    @State private var rate = ReplayRate.x30
    /// The setup sheet the record button opens — speed, photos, start.
    @State private var settingUp = false
    /// The cinema presentation, once the setup sheet has been answered.
    @State private var cinema: CinemaRun?

    /// Derived once per session rather than per redraw: playback moves the playhead 20×
    /// a second, and every one of those rebuilds this view's body.
    @State private var beats: [ReplayBeat] = []

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
                    // What the playhead is standing on, when it is standing on something.
                    // Without it the ticks are a row of anonymous coloured slivers.
                    if let beat = beatUnderPlayhead {
                        Text(beat.label)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(color(of: beat.kind))
                            .lineLimit(1)
                    }
                    Spacer()
                    if playhead != nil {
                        Button("Clear") { stop(); playhead = nil }
                            .font(.caption)
                    }
                }

                readout(range: range)
                controls(range: range)
                recordButton(range: range)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
            // A sheet where an action sheet used to be. Photos are not a fourth button —
            // see `ReplaySetupSheet`.
            .sheet(isPresented: $settingUp) {
                ReplaySetupSheet(detail: detail, milestones: milestones, span: range) {
                    pacing, framing, photos in
                    start(with: pacing, framing: framing, photos: photos)
                }
            }
            .fullScreenCover(item: $cinema) { run in
                ReplayCinemaView(detail: detail, milestones: milestones, span: range,
                                 pacing: run.pacing, record: run.record,
                                 framing: run.framing, photos: run.photos)
            }
            .task(id: detail.row.id) { beats = ReplayBeats.make(detail.analysis) }
            #if DEBUG && targetEnvironment(simulator)
            // `UI_REPLAY_CINEMA=<rate>` opens the cinema replay at that speed, since `simctl`
            // can tap neither the button nor the setup sheet. `UI_REPLAY_RECORD=0` stages the
            // *other* mode — the plain full-screen replay a rider gets when the recorder is
            // unavailable or the permission was refused — which is otherwise unreachable on a
            // machine where `isAvailable` happens to be true. Pair either with
            // `UI_REPLAY_CLIP=stub` (`ReplayRecorder`) to walk the clip sheet as well.
            // `UI_REPLAY_SETUP=1` opens the setup sheet instead, which is the one screen the
            // photo picker lives on.
            // `UI_REPLAY_LENGTH=10|25|60|full` opens the cinema at what the *picker* would
            // have resolved that choice to on this session — a raw rate says nothing about
            // whether the length arithmetic is right, and the length is now the control.
            // `UI_REPLAY_FRAMING=portrait|square|landscape|fullScreen` stages the letterbox,
            // which is otherwise behind the setup sheet's third picker.
            .task {
                let environment = ProcessInfo.processInfo.environment
                if environment["UI_REPLAY_SETUP"] == "1" { settingUp = true }
                let record = environment["UI_REPLAY_RECORD"] != "0"
                    && ReplayRecorder.isAvailable
                let framing = environment["UI_REPLAY_FRAMING"]
                    .flatMap(ReplayFraming.init(rawValue:)) ?? .fullScreen
                if let raw = environment["UI_REPLAY_LENGTH"],
                   let choice = ReplayClipLength(rawValue: raw == "full" ? "full" : "s\(raw)") {
                    cinema = CinemaRun(
                        pacing: choice.pacing(span: range, milestones: milestones),
                        record: record, framing: framing)
                    return
                }
                guard let raw = environment["UI_REPLAY_CINEMA"],
                      let speed = Double(raw) else { return }
                cinema = CinemaRun(pacing: ReplayPacing.Plan(rate: speed, ease: .cinema),
                                   record: record, framing: framing)
            }
            #endif
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

    /// Two rows rather than one. The transport used to sit beside the slider, which left
    /// the slider about 120 pt on a phone — a two-hour session at one pixel per fifteen
    /// seconds. With the skip buttons added there is no version of one row that works, so
    /// the bar gets the full width and the buttons get their own line.
    private func controls(range: ClosedRange<Double>) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 0) {
                beatBar(range: range)
                Slider(value: Binding(get: { playhead ?? range.lowerBound },
                                      set: { playhead = $0 }),
                       in: range)
                    .tint(.accentColor)
                    .accessibilityLabel("Replay position")
            }

            HStack(spacing: 16) {
                skip(to: ReplayBeats.beat(before: playheadOrStart(range), in: beats),
                     symbol: "backward.end.fill", label: "Previous marker")
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
                skip(to: ReplayBeats.beat(after: playheadOrStart(range), in: beats),
                     symbol: "forward.end.fill", label: "Next marker")

                Spacer(minLength: 8)

                commentaryToggle

                Picker("Speed", selection: $rate) {
                    ForEach(ReplayRate.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
        }
    }

    /// A skip button, disabled — rather than hidden — when there is nothing that way: a
    /// transport whose buttons move around as you use it is unusable.
    private func skip(to beat: ReplayBeat?, symbol: String, label: String) -> some View {
        Button {
            guard let beat else { return }
            playhead = beat.t
        } label: {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.plain)
        .disabled(beat == nil)
        .foregroundStyle(beat == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
        .accessibilityLabel(label)
        .accessibilityHint(beat.map { "Jump to \($0.label)" } ?? "")
    }

    private func playheadOrStart(_ range: ClosedRange<Double>) -> Double {
        playhead ?? range.lowerBound
    }

    /// The commentary switch: whether the replay talks while it plays.
    ///
    /// It sits on the transport row and not in Settings because it is a thing you change
    /// *while watching* — the second time a caption covers the jibe you were looking at is
    /// when you want it gone — and it is a filled/hollow symbol rather than a labelled
    /// toggle because the row already carries three transport buttons and a speed picker,
    /// and "Commentary" spelled out is wider than all of them.
    private var commentaryToggle: some View {
        Button {
            store.replayCommentary.toggle()
        } label: {
            Image(systemName: store.replayCommentary ? "text.bubble.fill" : "text.bubble")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.plain)
        .foregroundStyle(store.replayCommentary ? AnyShapeStyle(Color.accentColor)
                                                : AnyShapeStyle(.tertiary))
        .accessibilityLabel("Commentary")
        .accessibilityValue(store.replayCommentary ? "On" : "Off")
        .accessibilityHint("Comments on the session as the replay passes them")
    }

    // MARK: - Recording

    /// One presentation of the cinema replay. `Identifiable` so a second tap makes a genuinely
    /// new run rather than reusing the state of the last one.
    private struct CinemaRun: Identifiable {
        let id = UUID()
        /// The rate and the ease, already resolved from the length the rider picked
        /// (`ReplayPacing`). Carried as a pair because on a short clip the two are one
        /// decision — the dips had to be shortened to make that rate reach that length, and a
        /// run given the rate without the ease would be a different, longer clip.
        let pacing: ReplayPacing.Plan
        /// False when ReplayKit cannot capture — the replay still plays, it just plays for an
        /// audience of one.
        let record: Bool
        /// The clip's shape. Staged live and cropped afterwards — see `ReplayStage`.
        var framing: ReplayFraming = .fullScreen
        /// Already loaded and dated by the setup sheet, so the cinema view never waits on the
        /// photo library with a recording running.
        var photos: [ReplayPhoto] = []
    }

    /// "Record replay" — see the type comment for why it lives here.
    ///
    /// Offered even when the recorder is unavailable, because the same button then does the
    /// other useful half of the feature (the replay, full screen, with nothing around it) and
    /// the dialog says which of the two is about to happen. A button that vanished in Low
    /// Power Mode would just be a feature the rider could not find.
    private func recordButton(range: ClosedRange<Double>) -> some View {
        Button {
            stop()
            settingUp = true
        } label: {
            Label(ReplayRecorder.isAvailable ? "Record replay" : "Play replay full screen",
                  systemImage: ReplayRecorder.isAvailable ? "record.circle" : "play.rectangle")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Plays the session full screen and records it as a video clip")
    }

    private func start(with pacing: ReplayPacing.Plan, framing: ReplayFraming,
                       photos: [ReplayPhoto]) {
        cinema = CinemaRun(pacing: pacing, record: ReplayRecorder.isAvailable,
                           framing: framing, photos: photos)
    }

    // MARK: - Beat bar

    /// Height of the tick strip. Tall enough to read as a mark rather than as noise on the
    /// slider's own track, short enough that the card does not grow a row.
    private static let beatBarHeight: CGFloat = 14
    /// Half a slider thumb. `Slider` insets its track by the thumb's radius, and a tick
    /// drawn without the same inset drifts up to 14 pt away from the position it names —
    /// worst at the two ends, which is exactly where the first takeoff and the last jibe
    /// are. AppKit/UIKit expose no metric for it; 14 pt is the measured iOS 18 thumb.
    private static let thumbInset: CGFloat = 14
    /// How close a tap has to land to count as a tap on a tick. A 2 pt mark is not a
    /// target, so the bar takes the whole tap and resolves it to the nearest beat.
    private static let tapToleranceP: CGFloat = 16

    private func beatBar(range: ClosedRange<Double>) -> some View {
        GeometryReader { geometry in
            let usable = max(geometry.size.width - 2 * Self.thumbInset, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 3)
                    .frame(maxHeight: .infinity)
                ForEach(beats) { beat in
                    Capsule()
                        .fill(color(of: beat.kind))
                        .frame(width: 2.5, height: Self.beatBarHeight - 2)
                        .offset(x: Self.thumbInset - 1.25
                                + usable * CGFloat(fraction(of: beat.t, in: range)))
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .onTapGesture { location in
                let wanted = range.lowerBound
                    + Double((location.x - Self.thumbInset) / usable)
                    * (range.upperBound - range.lowerBound)
                guard let nearest = beats.min(by: {
                    abs($0.t - wanted) < abs($1.t - wanted)
                }) else { return }
                let distanceP = CGFloat(abs(nearest.t - wanted)
                    / (range.upperBound - range.lowerBound)) * usable
                guard distanceP <= Self.tapToleranceP else { return }
                playhead = nearest.t
            }
        }
        .frame(height: Self.beatBarHeight)
        .accessibilityElement()
        .accessibilityLabel("Session markers")
        .accessibilityValue("\(beats.count) markers")
    }

    private func fraction(of t: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((t - range.lowerBound) / span, 0), 1)
    }

    /// The beat the playhead is sitting on, within a couple of seconds — the tolerance the
    /// skip buttons already use, so "the button put me here" and "the label says where I
    /// am" can never disagree.
    private var beatUnderPlayhead: ReplayBeat? {
        guard let playhead else { return nil }
        return beats.min { abs($0.t - playhead) < abs($1.t - playhead) }
            .flatMap { abs($0.t - playhead) <= 2 ? $0 : nil }
    }

    /// Straight off the shared palette — a jibe's tick and its map marker are the same
    /// verdict and must be the same colour (`docs/presentation.md`). The two beats that are
    /// not verdicts borrow the effort and phase inks instead of inventing a hue.
    private func color(of kind: ReplayBeat.Kind) -> Color {
        switch kind {
        case .jibe(.flewThrough): DesignTokens.Outcome.flew
        case .jibe(.touchdown): DesignTokens.Outcome.touchdown
        case .jibe(.fellIn): DesignTokens.Outcome.fellIn
        case .takeoff(let free):
            free ? DesignTokens.Effort.takeoff.opacity(0.55) : DesignTokens.Effort.takeoff
        case .record: DesignTokens.Effort.window
        case .longestFlight: DesignTokens.Phase.flying
        }
    }

    private func stop() { isPlaying = false }
}
