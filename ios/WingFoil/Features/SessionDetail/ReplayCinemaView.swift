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
/// **Why the map does not follow the dot, but the rider's fingers can move it.** A camera
/// locked to the rider is a better *ride* and a worse *clip*: the viewer never sees the shape
/// of the session, and on a lake a following camera is thirty seconds of indistinguishable
/// blue. So the whole track is framed once (`detail.initialRegion` — the same camera the
/// inline map opens on) and the dot draws the afternoon as it goes. But a screen recording is
/// *live*, which makes interactivity free value that no offline renderer could offer: pinching
/// into the gybe corner while the clip records is a camera move in the finished video, and it
/// costs nothing but letting MapKit have its own gestures back. See `map`.
///
/// **Both orientations.** Nothing here is laid out against a fixed size: the map fills, and
/// the one band of text sits on the bottom safe-area edge. In landscape the map is wider and
/// the caption line is the same height, which is exactly the aspect a clip wants.
///
/// **What the clip is made of**, in order: a title card, the replay (with the rider's photos
/// spliced in where they were taken), any photos that had no moment, and a closing card. The
/// arithmetic behind all of that is `ReplayStoryboard`, in the kit, because it is what the
/// setup sheet quotes a length from before any of it exists.
struct ReplayCinemaView: View {

    let detail: SessionDetail
    /// The replay's commentary track — already filtered by the rider's toggle upstream, so an
    /// empty list means "no captions", and (see `storyboard`) no slow motion and no closing
    /// highlights either.
    let milestones: [ReplayMilestone]
    /// The session clock, from `SessionDetail.timeRange`. Non-optional: a session with no
    /// timeline never offers the button that gets here.
    let span: ClosedRange<Double>
    /// Session seconds per wall second — 10, 30 or 60, chosen before the view appeared.
    let rate: Double
    /// Whether to capture. False when ReplayKit said no or the phone cannot record, in which
    /// case this is simply a full-screen replay with no countdown and no clip at the end.
    let record: Bool
    /// The rider's own pictures, already loaded and dated by the setup sheet. Empty is the
    /// ordinary case and the whole photo path then costs nothing.
    var photos: [ReplayPhoto] = []

    /// Written by hand for two pieces of state that must be right on the *first* frame.
    ///
    /// `camera`, because the opening frame has to be the whole track and a `@State` that
    /// started `.automatic` and was corrected in `onAppear` would put one frame of the wrong
    /// camera at the top of the clip. And `storyboard`, because it is a function of nothing
    /// that changes for the life of this screen — resolving it in a computed property would
    /// rebuild two `DateFormatter`s and re-sort the photo list on every one of the twenty
    /// body passes a second the playhead causes.
    init(detail: SessionDetail, milestones: [ReplayMilestone], span: ClosedRange<Double>,
         rate: Double, record: Bool, photos: [ReplayPhoto] = []) {
        self.detail = detail
        self.milestones = milestones
        self.span = span
        self.rate = rate
        self.record = record
        self.photos = photos
        _camera = State(initialValue: .region(detail.initialRegion))
        _storyboard = State(initialValue: ReplayStoryboard.make(
            span: span, rate: rate, milestones: milestones,
            photos: photos.map(\.entry),
            place: SessionDisplay.title(detail.row),
            startedAt: detail.row.startDate))
    }

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
    /// The map camera, which the rider may move with his fingers while the clip records.
    /// Seeded in `init` so the first frame is already the whole track.
    @State private var camera: MapCameraPosition
    /// The whole clip's script, in the kit and pure: the driver's pacing (the milestone list
    /// feeds the ease, so the replay is at its slowest exactly while a caption is on screen),
    /// the two cards, and where each of the rider's photos lands. With the commentary switched
    /// off there are no milestones, no ease, no closing highlights and a plain constant-rate
    /// replay. Resolved once, in `init`.
    @State private var storyboard: ReplayStoryboard
    /// How many of the storyboard's splices have already played. A count rather than a
    /// position, because a splice pauses the replay *at* its own instant — see
    /// `ReplayStoryboard.nextSplice(shown:)`.
    @State private var splicesShown = 0
    /// The closing card's track, thinned once. `SessionDetail.shareOutline` walks every point
    /// of every segment, which is not a thing to do on a body pass — and the card is only ever
    /// shown at the very end, so it is built on the way into the outro.
    @State private var outline: TrackThumbnail?

    /// What the run is doing. Only `playing` moves the playhead.
    private enum Stage: Equatable {
        /// The first frame, held still: the track is drawn, nothing has started.
        case idle
        /// Counting in. Deliberately *before* the title card and before `startRecording`, so
        /// neither this nor the system's permission alert can land in the clip.
        case countdown(Int)
        /// The opening card. It goes up *before* the recorder is started — opaque, so it
        /// covers the countdown's last frame rather than merely replacing it — and it is
        /// still up for two and a half seconds after capture begins, which is what makes the
        /// first recorded frame a title rather than a "1".
        case title
        case playing
        /// One of the rider's photos, full screen, with the replay parked behind it. Carries
        /// the photo's id and whether it was placed inside the session (a splice) or is part
        /// of the closing run (a slide, which has no moment to stamp on it).
        case photo(id: String, stamped: Bool)
        /// The closing card: the session's key metrics and the commentary's own superlatives.
        /// It replaced a three-second hold on the last frame, which said nothing.
        case outro
        /// `stopRecording` is in flight — a second or two of file writing.
        case wrappingUp
        /// There is a clip; the sheet is offering it.
        case clip(URL)

        /// The run is in flight — the stop control means something and a trip to the
        /// background is an interruption.
        var isRunning: Bool {
            switch self {
            case .title, .playing, .photo, .outro: true
            default: false
            }
        }

        var photoID: String? {
            if case .photo(let id, _) = self { return id }
            return nil
        }

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
    private static let countdownFrom = 3
    /// How long the stop control stays up after a tap. It *is* in the clip while it shows,
    /// so it goes away on its own.
    private static let controlDwellS = 3.0
    /// The gap between the title card going up and `startRecording` being asked for.
    ///
    /// This is the fix for "the countdown's 1 is briefly visible in the clip". The old order
    /// removed the countdown and started the recorder in the same breath, and ReplayKit
    /// begins capturing from whatever is on the glass at that instant — which, one runloop
    /// after a `withAnimation` took a numeral away, is still the numeral. Four tenths of a
    /// second is several frames at any refresh rate: long enough that the card behind it has
    /// certainly been presented, short enough that nobody waits for it.
    ///
    /// The *recorded* buffer the clip actually needs is bigger than this and free: the first
    /// two and a half seconds of the video are a static title card, so the replay's own first
    /// frame is nowhere near the start of the file.
    private static let titleSettleS = 0.4

    private var driver: ReplayDriver { storyboard.driver }

    /// The 2 s peak's window, always — a clip is a highlight reel and the fastest two seconds
    /// of the afternoon is the one highlight every rider quotes. Not the session detail
    /// page's *selected* record, which is a browsing state and has no business in a video.
    private var effort: SessionDetail.RecordEffort? {
        detail.efforts.first { $0.id == RecordWindowSelection.defaultKey }
    }

    /// What the closing card prints — the *share card's* content pipeline, `complete` preset,
    /// unchanged. Two exports of one afternoon (the PNG a rider posts and the last frame of
    /// the clip he sends) must never name different numbers, and the only way to guarantee
    /// that is for there to be one place the numbers come from.
    private var outroStats: ShareCardStats {
        ShareCardStats.make(row: detail.row, title: SessionDisplay.title(detail.row),
                            metrics: KeyMetrics.make(summary: detail.analysis.summary,
                                                     records: detail.analysis.records),
                            preset: .complete)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Behind the map, so a rotation or a safe-area inset shows black rather than the
            // system background flashing through a frame of video.
            Color.black.ignoresSafeArea()
            map
            bottomBand
            // The four full-screen frames, over the map and under the transport. Each is
            // opaque and edge-to-edge, which is what lets the one underneath it change (or
            // disappear) without a single frame of the change reaching the video.
            // Each takes the reveal tap itself: a card covers the map, and a rider who wants
            // out during the four seconds of the outro must not have to wait for it.
            if let id = stage.photoID, let photo = photos.first(where: { $0.id == id }) {
                ReplayPhotoFrame(image: photo.image, stamp: photoStamp(for: id))
                    .onTapGesture { revealControls() }
            }
            if stage == .title {
                ReplayTitleCardView(card: storyboard.title,
                                    fallbackTitle: SessionDisplay.title(detail.row))
                    .transition(.opacity)
                    .onTapGesture { revealControls() }
            }
            if stage == .outro {
                ReplayOutroCardView(stats: outroStats, highlights: storyboard.highlights,
                                    thumbnail: outline)
                    .transition(.opacity)
                    .onTapGesture { revealControls() }
            }
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
    /// app the rider actually has.
    ///
    /// **The camera is the rider's, and MapKit's own gestures move it.** This is the one
    /// place in the app where a live screen recording pays for itself twice: a pinch into the
    /// corner where the jibes are, or a drag along the reach, is *in the finished video* —
    /// a camera move no offline renderer would have offered, for the price of handing MapKit
    /// back the two gestures it already implements. So the interaction modes are `.pan` and
    /// `.zoom` rather than the empty set they used to be, and `position` is a binding rather
    /// than an initial camera so "fit the whole track again" has something to write to.
    ///
    /// **Rotate and pitch are deliberately not in the set.** A clip of a session is a clip of
    /// a *map*, and a viewer who has to work out which way is north before they can read the
    /// track has been given a worse video. A two-finger twist is also the easiest gesture in
    /// the world to make by accident while pinching.
    ///
    /// **Tap still means "show me the stop button", and cannot mean anything else.** It is a
    /// `simultaneousGesture` rather than `.onTapGesture` precisely because MapKit now has
    /// recognizers of its own: `simultaneous` does not wait for them to fail, so the escape
    /// hatch out of a running recording can never be swallowed by a map that thinks the tap
    /// was for it. A tap is not a pinch and not a drag, so there is nothing for it to
    /// conflict with in the other direction.
    private var map: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            TrackContent(detail: detail, effort: effort, visibility: store.mapLayers,
                         playhead: detail.moment(at: playhead), direction: direction)
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        // Still `.onEnd`, and now it earns its keep: the chevron spacing is measured in
        // screen points, so a rider who zooms in mid-clip gets the arrows re-decimated for
        // the scale he zoomed to rather than the one the clip opened on.
        .onMapCameraChange(frequency: .onEnd) { context in
            direction.camera(moved: context, detail: detail)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            direction.resized(to: size, detail: detail)
        }
        .ignoresSafeArea()
        .simultaneousGesture(TapGesture().onEnded { revealControls() })
    }

    /// Back to the whole track, animated so the move reads as a camera move rather than as a
    /// cut. A button and not a double-tap: MapKit's own double-tap is zoom-in, and stealing
    /// it would break the gesture a rider expects from every other map on the phone.
    private func fitTrack() {
        withAnimation(.easeInOut(duration: 0.55)) {
            camera = .region(detail.initialRegion)
        }
    }

    /// Caption, clock, speed and the progress hairline — the whole of the chrome, in one band
    /// along the bottom edge where it cannot cover the dot it is about.
    private var bottomBand: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            if let comment {
                // `.cinema` and not the inline map's size: this caption is read by somebody
                // else, off a video, in a chat app, at whatever size that app decided to
                // play it. See `ReplayCommentaryBubble.Size`.
                ReplayCommentaryBubble(milestone: comment, size: .cinema)
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
                HStack(spacing: 10) {
                    Spacer()
                    // Rides with the stop button because it is the other thing a rider wants
                    // during a run and the other thing that must not be permanently on
                    // screen: after a pinch, "put the whole session back" is one tap away
                    // and then gone again with the same three-second timer.
                    Button {
                        controlsTapped += 1
                        fitTrack()
                    } label: {
                        pill("Fit track", "arrow.up.left.and.down.right.magnifyingglass",
                             ink: .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fit the whole track")

                    Button {
                        controlsVisible = false
                        stopRequested = true
                    } label: {
                        pill(stopLabel, stopSymbol,
                             ink: stopsARecording ? Color.red : Color.primary)
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

    private func pill(_ title: String, _ symbol: String, ink: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: .capsule)
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

    /// Count in, raise the title card, start the recorder, play, show the leftover photos,
    /// close on the outro, stop, offer the clip.
    ///
    /// Written as one sequential function rather than a state machine spread over five
    /// `.task(id:)`s because that is what it is: a script with one branch in it. The view's
    /// own `.task` cancels it on the way out, so there is no path where a run outlives the
    /// screen it is drawing on.
    ///
    /// **The order of the first four lines is the whole of the "the countdown is in the clip"
    /// fix**, and it is worth spelling out because the obvious order is the broken one:
    ///
    /// 1. the countdown finishes and the **title card goes up**, opaque and full-screen, in a
    ///    transaction with no animation — a fade would put a translucent "1" on the glass for
    ///    the length of the fade;
    /// 2. `titleSettleS` passes, which is what actually guarantees the numeral is gone from
    ///    the *rendered* frame rather than merely from the view tree;
    /// 3. only then is ReplayKit asked to start, and awaited to completion — capture begins on
    ///    a frame that has been nothing but the title card for four tenths of a second;
    /// 4. the card is then held for its own two and a half seconds, so the replay's first
    ///    frame is nowhere near the beginning of the file.
    private func run() async {
        playhead = driver.start
        stopRequested = false
        splicesShown = 0
        stage = .idle

        #if DEBUG && targetEnvironment(simulator)
        // `UI_REPLAY_STAGE=title|outro` parks the run on one of the two cards and leaves it
        // there. They are otherwise on screen for two and a half and four seconds inside a
        // run that `simctl` cannot pause, which is not a window a screenshot fits through.
        if let wanted = ProcessInfo.processInfo.environment["UI_REPLAY_STAGE"] {
            playhead = wanted == "outro" ? span.upperBound : span.lowerBound
            if wanted == "outro" { outline = detail.shareOutline }
            stage = wanted == "outro" ? .outro : .title
            return
        }
        #endif

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
            // No animation, deliberately — see the comment above.
            stage = .title
            try? await Task.sleep(for: .seconds(Self.titleSettleS))
            if Task.isCancelled { return }
            if stopRequested {
                dismiss()
                return
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
        } else {
            stage = .title
        }

        // The recorded life of the title card — the number the setup sheet quoted.
        try? await Task.sleep(for: .seconds(storyboard.timing.titleS))
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.3)) { stage = .playing }
        await play()
        guard !Task.isCancelled else { return }

        // A run that reached the end gets its tail; one the rider stopped does not — they
        // asked for it to be over.
        if !stopRequested {
            await slideshow()
            guard !Task.isCancelled else { return }
            if outline == nil { outline = detail.shareOutline }
            withAnimation(.easeInOut(duration: 0.35)) { stage = .outro }
            try? await Task.sleep(for: .seconds(storyboard.timing.outroS))
            guard !Task.isCancelled else { return }
        }
        await finish()
    }

    /// The playhead loop. Everything about *where* it goes is `ReplayDriver`; all this owns
    /// is the clock it is asked on — and the one thing that stops the clock, which is a photo
    /// the rider took at this moment of the afternoon.
    private func play() async {
        let step = 1 / Self.ticksPerSecond
        let nanos = UInt64(1_000_000_000 / Self.ticksPerSecond)
        while !Task.isCancelled && !stopRequested {
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, !stopRequested else { return }
            playhead = driver.advance(playhead, byWallSeconds: step)
            // A `while` and not an `if`: one tick at 60× is three seconds of session, which
            // is long enough to step over two frames of a burst. Both then play, back to
            // back, which is what a burst should look like.
            while let next = storyboard.nextSplice(shown: splicesShown), playhead >= next.t {
                splicesShown += 1
                await hold(photo: next.photo, seconds: next.holdS, stamped: true)
                guard !Task.isCancelled, !stopRequested else { return }
            }
            if driver.hasFinished(playhead) { return }
        }
    }

    /// One photo, full screen, with the replay parked behind it.
    ///
    /// The playhead is simply not advanced while this runs — the loop above is awaiting it —
    /// so the replay resumes on the frame it was interrupted on rather than jumping forward
    /// by the length of the pause. That is the difference between a photo *in* the session
    /// and a photo over it.
    private func hold(photo id: String, seconds: Double, stamped: Bool) async {
        guard photos.contains(where: { $0.id == id }) else { return }
        withAnimation(.easeInOut(duration: 0.3)) { stage = .photo(id: id, stamped: stamped) }
        try? await Task.sleep(for: .seconds(seconds))
        guard !Task.isCancelled, !stopRequested else { return }
        withAnimation(.easeInOut(duration: 0.3)) { stage = .playing }
    }

    /// The photos that had no moment to be spliced into, between the last frame of the replay
    /// and the closing card. No time stamp on them: a picture that cannot say when it was
    /// taken must not be captioned with a moment it might not belong to.
    private func slideshow() async {
        for id in storyboard.slideshow {
            guard !Task.isCancelled, !stopRequested else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                stage = .photo(id: id, stamped: false)
            }
            try? await Task.sleep(for: .seconds(storyboard.timing.slideS))
        }
    }

    /// The elapsed clock under a spliced photo — the scrubber's own `m:ss`, so "3:12" on a
    /// picture and "3:12" under the map are the same instant.
    private func photoStamp(for id: String) -> String? {
        guard case .photo(_, let stamped) = stage, stamped,
              let splice = storyboard.splices.first(where: { $0.photo == id }) else {
            return nil
        }
        return Fmt.clock(splice.t - span.lowerBound)
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
        // `.playing` and nothing else. The old test was "the run is in flight", which now
        // includes three stages that have a card or a photo over the map: a caption that
        // changed underneath one of those would be a caption nobody sees appear and everybody
        // sees already-changed when the card lifts.
        guard stage == .playing, !milestones.isEmpty else { return nil }
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
