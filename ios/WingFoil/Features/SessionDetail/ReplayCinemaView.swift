import AVKit
import MapKit
import SwiftUI
import WingFoilKit

/// The replay with everything else taken away: a full-screen map, the track, the moving dot,
/// the commentary — and no app around it.
///
/// **Why a separate presentation and not "the map, bigger".** This view is the *renderer* for
/// a shareable clip (`ReplayRecorder`), which means every pixel on the glass ends up in the
/// video. A tab chip, a scrub bar or a navigation title in the corner is a screenshot of an
/// app; what a rider wants to send is a session. So the chrome is not hidden, it is absent —
/// the only things drawn are the ones that say something about the afternoon: where he went,
/// where he is now, what just happened, and how far through it is.
///
/// **Why the map does not follow the dot.** A camera locked to the rider is a better *ride*
/// and a worse *clip*: the viewer never sees the shape of the session, and on a lake a
/// following camera is thirty seconds of indistinguishable blue. The whole track, framed once
/// (`detail.initialRegion` — the same camera the inline map opens on), lets the dot draw the
/// afternoon as it goes.
///
/// **Both orientations.** Nothing here is laid out against a fixed size: the map fills, and
/// the one band of text sits on the bottom safe-area edge. In landscape the map is wider and
/// the caption line is the same height, which is exactly the aspect a clip wants.
struct ReplayCinemaView: View {

    let detail: SessionDetail
    /// The replay's commentary track — already filtered by the rider's toggle upstream, so an
    /// empty list means "no captions", and (see `driver`) no slow motion either.
    let milestones: [ReplayMilestone]
    /// The session clock, from `SessionDetail.timeRange`. Non-optional: a session with no
    /// timeline never offers the button that gets here.
    let span: ClosedRange<Double>
    /// Session seconds per wall second — 10, 30 or 60, chosen before the view appeared.
    let rate: Double
    /// Whether to capture. False when ReplayKit said no or the phone cannot record, in which
    /// case this is simply a full-screen replay with no countdown and no clip at the end.
    let record: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// The legend chips' state, read here for the same reason `FullScreenMapView` reads it:
    /// a layer the rider switched off must not reappear in the video.
    @Environment(SessionStore.self) private var store

    /// Session-clock seconds under the playhead. The one piece of state the whole frame is a
    /// function of.
    @State private var playhead: Double = 0
    @State private var stage = Stage.idle
    @State private var recorder = ReplayRecorder()
    /// Bumped to re-run the whole sequence — the "watch it anyway" answer to a permission
    /// refusal replays the view rather than trying to unwind the failed run in place.
    @State private var generation = 0
    /// Cleared by `generation`; false on a run the rider asked not to record.
    @State private var recordThisRun = true
    /// Set by the stop control and by a trip to the background. Read by the play loop, which
    /// is the only thing allowed to end a run early.
    @State private var stopRequested = false
    /// The transport is invisible until the glass is tapped — see `transport`.
    @State private var controlsVisible = false
    /// Bumped by every tap, so the hide countdown restarts rather than stacking up.
    @State private var controlsTapped = 0
    @State private var failure: FailureNote?
    @State private var startedRecordingAt: Date?
    @State private var recordedWallS: Double = 0
    /// The caption on screen right now — same dwell rule as the inline map's.
    @State private var comment: ReplayMilestone?
    @State private var direction = DirectionField()

    /// What the run is doing. Only `playing` and `outro` move the playhead.
    private enum Stage: Equatable {
        /// The first frame, held still: the track is drawn, nothing has started.
        case idle
        /// Counting in. Deliberately *before* `startRecording`, so neither this nor the
        /// system's permission alert can land in the clip.
        case countdown(Int)
        case playing
        /// The playhead is parked on the last sample while the closing caption is read. A
        /// clip that cut on the frame the session ended would lose the line that sums it up.
        case outro
        /// `stopRecording` is in flight — a second or two of file writing.
        case wrappingUp
        /// There is a clip; the sheet is offering it.
        case clip(URL)

        var isRunning: Bool { self == .playing || self == .outro }

        var clipURL: URL? {
            if case .clip(let url) = self { return url }
            return nil
        }
    }

    private struct FailureNote: Equatable {
        let message: String
        /// Whether "watch it without recording" is a sensible offer — it is for a permission
        /// refusal, and it is not for a clip that was lost after the run already happened.
        let canWatch: Bool
    }

    // MARK: - Pacing

    /// Ticks per second of wall clock, the scrubber's own 20: smooth to the eye, and cheap
    /// enough that the phone does not warm up while it is also encoding video.
    private static let ticksPerSecond = 20.0
    /// How long a caption stays up. Half a second longer than the inline map's 2.5 s, because
    /// the reader of a clip did not choose the moment they started watching.
    private static let commentaryDwellS = 3.0
    /// The tail after the last sample — long enough for the closing line, short enough that
    /// the clip does not end on a still.
    private static let outroS = 3.0
    private static let countdownFrom = 3
    /// How long the stop control stays up after a tap. It *is* in the clip while it shows,
    /// so it goes away on its own.
    private static let controlDwellS = 3.0

    /// The pacing, in the kit and pure (`ReplayDriver`): the milestone list feeds the ease, so
    /// the replay is at its slowest exactly while a caption is on screen. With the commentary
    /// switched off there are no milestones, no ease, and a plain constant-rate replay.
    private var driver: ReplayDriver {
        ReplayDriver(span: span, rate: rate, easeAt: milestones.map(\.t))
    }

    /// The 2 s peak's window, always — a clip is a highlight reel and the fastest two seconds
    /// of the afternoon is the one highlight every rider quotes. Not the session detail
    /// page's *selected* record, which is a browsing state and has no business in a video.
    private var effort: SessionDetail.RecordEffort? {
        detail.efforts.first { $0.id == RecordWindowSelection.defaultKey }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Behind the map, so a rotation or a safe-area inset shows black rather than the
            // system background flashing through a frame of video.
            Color.black.ignoresSafeArea()
            map
            bottomBand
            if case .countdown(let count) = stage { countdown(count) }
            if stage == .wrappingUp { wrappingUp }
            transport
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task(id: generation) { await run() }
        // The stop control hides itself. Keyed on the tap count so a second tap restarts the
        // wait instead of the first one's timer taking the button away mid-press.
        .task(id: controlsTapped) {
            guard controlsTapped > 0 else { return }
            try? await Task.sleep(for: .seconds(Self.controlDwellS))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { controlsVisible = false }
        }
        // One caption at a time, for as long as it is news — the inline map's rule, with the
        // same reason for keying on the id: two milestones close together must replace each
        // other instantly rather than queue.
        .task(id: currentMilestone?.id) { await show(currentMilestone) }
        // Nothing here is a touch, and a 78 s clip at 10× is comfortably longer than the
        // shortest auto-lock: without this the screen dims into the middle of the recording.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        // `.background` only, never `.inactive`: the permission alert and a Control Center
        // pull both make the scene inactive, and treating those as interruptions would abort
        // every recording at the moment it started.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background, stage.isRunning else { return }
            stopRequested = true
        }
        .alert("Replay", isPresented: Binding(get: { failure != nil },
                                              set: { if !$0 { failure = nil } }),
               presenting: failure) { note in
            if note.canWatch {
                Button("Watch without recording") { replay(recording: false) }
            }
            Button(note.canWatch ? "Close" : "OK", role: .cancel) { dismiss() }
        } message: { note in
            Text(note.message)
        }
        .sheet(isPresented: Binding(get: { stage.clipURL != nil },
                                    set: { if !$0 { dismiss() } })) {
            if let url = stage.clipURL {
                ReplayClipSheet(url: url, title: SessionDisplay.title(detail.row),
                                wallS: recordedWallS,
                                discard: {
                                    recorder.discard()
                                    stage = .idle
                                    dismiss()
                                },
                                done: {
                                    stage = .idle
                                    dismiss()
                                })
            }
        }
    }

    // MARK: - The picture

    /// The same `TrackContent` the inline and full-screen maps draw, so the video is of the
    /// app the rider actually has. Interaction is off: the only tap this screen answers is
    /// "show me the stop button".
    private var map: some View {
        Map(initialPosition: .region(detail.initialRegion), interactionModes: []) {
            TrackContent(detail: detail, effort: effort, visibility: store.mapLayers,
                         playhead: detail.moment(at: playhead), direction: direction)
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { context in
            direction.camera(moved: context, detail: detail)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            direction.resized(to: size, detail: detail)
        }
        .ignoresSafeArea()
        .contentShape(.rect)
        .onTapGesture { revealControls() }
    }

    /// Caption, clock, speed and the progress hairline — the whole of the chrome, in one band
    /// along the bottom edge where it cannot cover the dot it is about.
    private var bottomBand: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            if let comment {
                ReplayCommentaryBubble(milestone: comment)
                    .padding(.horizontal, 14)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(spacing: 8) {
                chip(Fmt.clock(playhead - span.lowerBound))
                Spacer(minLength: 0)
                // Said out loud, because a viewer who does not know the clip is sped up will
                // read a 30× jibe as an impossible one.
                chip("\(Int(rate))×")
            }
            .padding(.horizontal, 14)
            progressHairline
        }
        .padding(.bottom, 6)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.thinMaterial, in: .capsule)
    }

    /// Two and a half points of "how far through are we". Enough to orient a viewer who
    /// joined the clip halfway; not enough to be a control anybody tries to drag.
    private var progressHairline: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * driver.progress(at: playhead))
            }
        }
        .frame(height: 2.5)
        .padding(.horizontal, 14)
    }

    // MARK: - The two overlays that are not in the clip

    /// 3 · 2 · 1, over the first frame, before the recorder is even asked to start.
    private func countdown(_ count: Int) -> some View {
        VStack(spacing: 10) {
            Text("\(count)")
                .font(.system(size: 96, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText(countsDown: true))
            Text("Recording starts when the count ends")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
        .transition(.opacity)
    }

    private var wrappingUp: some View {
        ProgressView("Saving the clip…")
            .padding(20)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
    }

    // MARK: - The transport, such as it is

    /// One button, hidden until the glass is tapped and gone again three seconds later.
    ///
    /// It has to exist — a rider who started a 78 s clip by mistake must be able to get out —
    /// and it has to be invisible, because anything permanently on screen is permanently in
    /// the video. Tap to reveal is the compromise: the button is in the clip for the three
    /// seconds around the tap that produced it, which is a fair price for an escape hatch.
    @ViewBuilder
    private var transport: some View {
        if controlsVisible {
            VStack {
                HStack {
                    Spacer()
                    Button {
                        controlsVisible = false
                        stopRequested = true
                    } label: {
                        Label(stopLabel, systemImage: stopSymbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(stopsARecording ? Color.red : Color.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(.ultraThinMaterial, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .transition(.opacity)
        }
    }

    /// Whether the button in the corner ends a recording or merely closes a replay — the one
    /// place the two modes look different, and they must, because one of them is destructive
    /// of something the rider is halfway through making.
    private var stopsARecording: Bool { record && recordThisRun && recorder.isRecording }

    private var stopLabel: String { stopsARecording ? "Stop" : "Done" }
    private var stopSymbol: String {
        stopsARecording ? "stop.circle.fill" : "xmark.circle.fill"
    }

    private func revealControls() {
        withAnimation(.snappy(duration: 0.2)) { controlsVisible = true }
        controlsTapped += 1
    }

    // MARK: - The run

    /// Count in, start the recorder, play, hold for the closing line, stop, offer the clip.
    ///
    /// Written as one sequential function rather than a state machine spread over five
    /// `.task(id:)`s because that is what it is: a script with one branch in it. The view's
    /// own `.task` cancels it on the way out, so there is no path where a run outlives the
    /// screen it is drawing on.
    private func run() async {
        playhead = driver.start
        stopRequested = false
        stage = .idle

        if record && recordThisRun {
            for count in stride(from: Self.countdownFrom, through: 1, by: -1) {
                withAnimation(.snappy(duration: 0.2)) { stage = .countdown(count) }
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                // The escape hatch works during the count too — this is exactly when a rider
                // realises they picked the wrong speed, and nothing has been recorded yet.
                if stopRequested {
                    dismiss()
                    return
                }
            }
            do {
                try await recorder.start()
                startedRecordingAt = .now
            } catch {
                // Permission refused, or the recorder went away between the button and here.
                // Either way the replay itself is still worth watching, so the alert offers
                // it rather than throwing the rider back to the session page.
                failure = FailureNote(
                    message: (error as? any LocalizedError)?.errorDescription
                        ?? error.localizedDescription,
                    canWatch: true)
                stage = .idle
                return
            }
        }

        withAnimation(.easeOut(duration: 0.25)) { stage = .playing }
        await play()
        guard !Task.isCancelled else { return }

        // A run that reached the end gets its tail; one the rider stopped does not — they
        // asked for it to be over.
        if !stopRequested {
            stage = .outro
            try? await Task.sleep(for: .seconds(Self.outroS))
            guard !Task.isCancelled else { return }
        }
        await finish()
    }

    /// The playhead loop. Everything about *where* it goes is `ReplayDriver`; all this owns
    /// is the clock it is asked on.
    private func play() async {
        let step = 1 / Self.ticksPerSecond
        let nanos = UInt64(1_000_000_000 / Self.ticksPerSecond)
        while !Task.isCancelled && !stopRequested {
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, !stopRequested else { return }
            playhead = driver.advance(playhead, byWallSeconds: step)
            if driver.hasFinished(playhead) { return }
        }
    }

    /// Stop the recorder and decide what the rider is left holding.
    private func finish() async {
        guard recorder.isRecording else {
            dismiss()
            return
        }
        recordedWallS = startedRecordingAt.map { Date.now.timeIntervalSince($0) } ?? 0
        stage = .wrappingUp
        do {
            if let url = try await recorder.stop(named: ReplayRecorder.clipName(for: detail.row)) {
                stage = .clip(url)
            } else {
                dismiss()
            }
        } catch {
            // The run happened and the file did not survive it — an interruption, or a
            // system-initiated stop. Nothing to offer and nothing to watch again, so this
            // alert has one button.
            failure = FailureNote(
                message: (error as? any LocalizedError)?.errorDescription
                    ?? error.localizedDescription,
                canWatch: false)
            stage = .idle
        }
    }

    /// Start the whole script over — used by the "watch without recording" answer to a
    /// permission refusal.
    private func replay(recording: Bool) {
        recordThisRun = recording
        failure = nil
        generation += 1
    }

    // MARK: - Commentary

    /// The line the playhead has most recently passed, and nil while nothing is playing —
    /// the opening caption must not be burned through by the countdown before the recorder
    /// has even started.
    private var currentMilestone: ReplayMilestone? {
        guard stage.isRunning, !milestones.isEmpty else { return nil }
        return ReplayCommentary.current(at: playhead, in: milestones)
    }

    private func show(_ milestone: ReplayMilestone?) async {
        guard let milestone else {
            withAnimation(.easeOut(duration: 0.3)) { comment = nil }
            return
        }
        withAnimation(.snappy(duration: 0.2)) { comment = milestone }
        try? await Task.sleep(for: .seconds(Self.commentaryDwellS))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) { comment = nil }
    }
}

/// What the rider is left with: the clip, playable, with the two things you can do to it.
///
/// Presented the same way the FIT share is — a `ShareLink` over a temp-file URL, prominent,
/// with the size on the label — because it is the same promise: nothing is uploaded, the file
/// is handed straight to the share sheet.
///
/// The player is here so "discard" is a real decision rather than a guess. A clip is the one
/// export in the app whose quality depends on what the phone was doing while it was made, and
/// the only way to know it came out is to watch it.
private struct ReplayClipSheet: View {
    let url: URL
    let title: String
    /// Wall seconds actually captured — the run's own measurement, not a probe of the file.
    let wallS: Double
    let discard: () -> Void
    let done: () -> Void

    /// Built once, in `onAppear`: a player rebuilt in `body` would restart from the first
    /// frame every time the size label or the share sheet caused a redraw.
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // No fixed aspect: a clip recorded in landscape is as legitimate as one
                // recorded upright, and a 9:16 box would letterbox one of them into a strip.
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, minHeight: 240, maxHeight: 320)
                    .background(Color.black, in: .rect(cornerRadius: 14))
                    .clipShape(.rect(cornerRadius: 14))

                Text("\(Fmt.duration(wallS)) · \(Fmt.bytes(ReplayRecorder.size(of: url))) · "
                     + url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                ShareLink(item: url, subject: Text(title), message: Text(Self.invitation)) {
                    Label("Share clip", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(role: .destructive, action: discard) {
                    Label("Discard", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .onAppear { if player == nil { player = AVPlayer(url: url) } }
            .navigationTitle("Replay clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                }
            }
        }
    }

    /// The same line the shared FIT carries, for the same reason: whoever gets the clip
    /// should be able to find out what made it.
    private static let invitation =
        "\(Branding.appName) replay — \(Branding.siteURL)"
}
