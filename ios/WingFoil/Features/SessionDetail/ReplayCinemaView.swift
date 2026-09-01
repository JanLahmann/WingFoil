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
    /// The session clock, from `SessionDetail.timeRange`. Non-optional: a session with no
    /// timeline never offers the button that gets here.
    let span: ClosedRange<Double>
    /// The pace, resolved from the length the rider picked in the setup sheet
    /// (`ReplayPacing`): session seconds per wall second, the slow-motion ease that rate was
    /// solved against, and the script both were solved for. The three travel together because
    /// on a short clip they are one decision — see `ReplayScrubber.CinemaRun`.
    let pacing: ReplayPacing.Plan

    /// The replay's commentary track — already filtered by the rider's toggle upstream and cut
    /// to what a clip this long has room to say, so an empty list means "no captions", and (see
    /// `storyboard`) no slow motion and no closing highlights either.
    ///
    /// Read off the plan rather than passed in beside it, which is what makes "the run is at
    /// its slowest exactly while a caption is on screen" true by construction rather than by
    /// two callers agreeing.
    private var milestones: [ReplayMilestone] { pacing.milestones }
    /// Whether to capture. False when ReplayKit said no or the phone cannot record, in which
    /// case this is simply a full-screen replay with no countdown and no clip at the end.
    let record: Bool
    /// The shape the finished clip should be (`ReplayFraming`). The replay is drawn inside a
    /// box of that ratio and the rest of the glass is painted out, so the rider composes
    /// against the frame he will get; the crop that follows the recording is exactly that box
    /// (`ReplayStage`, `finish`).
    var framing: ReplayFraming = .fullScreen
    /// The rider's own pictures, already loaded and dated by the setup sheet. Empty is the
    /// ordinary case and the whole photo path then costs nothing.
    var photos: [ReplayPhoto] = []
    /// The track to lay under the finished clip, or nil for silence. Nothing is played *while*
    /// the replay runs — the music is muxed onto the recording afterwards (`finish`), which is
    /// the only way it can be a clean track rather than a room recording, and also the only way
    /// it can be there at all with the microphone off.
    var music: URL?

    /// Written by hand for two pieces of state that must be right on the *first* frame.
    ///
    /// `camera`, because the opening frame has to be the whole track and a `@State` that
    /// started `.automatic` and was corrected in `onAppear` would put one frame of the wrong
    /// camera at the top of the clip. And `storyboard`, because it is a function of nothing
    /// that changes for the life of this screen — resolving it in a computed property would
    /// rebuild two `DateFormatter`s and re-sort the photo list on every one of the twenty
    /// body passes a second the playhead causes.
    init(detail: SessionDetail, span: ClosedRange<Double>,
         pacing: ReplayPacing.Plan, record: Bool, framing: ReplayFraming = .fullScreen,
         photos: [ReplayPhoto] = [], music: URL? = nil) {
        self.detail = detail
        self.span = span
        self.pacing = pacing
        self.record = record
        self.framing = framing
        self.photos = photos
        self.music = music
        _camera = State(initialValue: .region(detail.initialRegion))
        _storyboard = State(initialValue: ReplayStoryboard.make(
            span: span, rate: pacing.rate, milestones: pacing.milestones,
            photos: photos.map(\.entry),
            place: SessionDisplay.title(detail.row),
            startedAt: detail.row.startDate, timeZone: detail.row.displayZone,
            ease: pacing.ease))
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
    /// Where the clip's frame is on the glass, and how big the glass is — both measured rather
    /// than assumed, and both needed *after* the run to turn the staged box into a crop in the
    /// recorded file's pixels (`ReplayStage.crop`).
    @State private var stageRect: CGRect = .zero
    @State private var glassSize: CGSize = .zero
    /// Set when the crop was asked for and could not be done, so the sheet can offer the
    /// full-screen recording and say what happened rather than quietly handing back the wrong
    /// shape.
    @State private var framingNote: String?
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
        ShareCardStats.outro(row: detail.row, title: SessionDisplay.title(detail.row),
                             metrics: KeyMetrics.make(summary: detail.analysis.summary,
                                                      records: detail.analysis.records),
                             longestFlightS: detail.analysis.summary.longestFlightS,
                             timeZone: detail.row.displayZone)
    }

    // MARK: - Body

    /// The clip's own frame, staged live.
    ///
    /// **Why the framing is drawn and not only cropped.** ReplayKit records the glass — there
    /// is no API that records part of it — so a 9:16 clip has to be cut out afterwards either
    /// way. But a rider who could not *see* the frame while it recorded would be composing
    /// blind: the pinch that centres the jibe corner on the glass would leave it half outside
    /// the clip, and he would only find that out when he watched it back. So the replay is
    /// drawn inside the box, the rest of the glass is painted out, and the crop that follows
    /// is exactly the box he was looking at (`ReplayStage`, `finish`).
    ///
    /// The `GeometryReader` reports the *inset* size, so the glass is that plus the safe-area
    /// insets and the stage is positioned back in glass coordinates. That matters because the
    /// recorder captures the glass: a stage rect measured inside the insets would be a status
    /// bar's height out, and every clip would be cropped a few pixels low.
    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let glass = CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                               height: proxy.size.height + insets.top + insets.bottom)
            let box = ReplayStage.rect(in: glass, framing: framing)
            ZStack {
                // The letterbox. Black rather than the brand navy: a video's bars are black
                // everywhere, and a coloured border reads as part of the picture.
                Color.black.ignoresSafeArea()
                staged(box: box, insets: insets, glass: glass)
                // Outside the stage on purpose. The transport is the one thing on screen that
                // is *not* part of the clip, and in every framing but full screen it now sits
                // in the letterbox, where the crop cannot reach it at all.
                transport
            }
            .onGeometryChange(for: CGRect.self) { _ in box } action: { stageRect = $0 }
            .onGeometryChange(for: CGSize.self) { _ in glass } action: { glassSize = $0 }
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
                                startedAt: detail.row.startDate,
                                timeZone: detail.row.displayZone,
                                wallS: recordedWallS, note: framingNote,
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

    /// Everything that ends up in the clip, inside the box and clipped to it.
    ///
    /// `.position` in the reader's own (inset) coordinate space, offset back by the insets, so
    /// the box lands where `ReplayStage` said it does *on the glass* — which is the space the
    /// recorder captures and therefore the space the crop is computed in.
    private func staged(box: CGRect, insets: EdgeInsets, glass: CGSize) -> some View {
        ZStack {
            // Opaque under the map: a rotation mid-run must show black rather than the system
            // background flashing through a frame of video.
            Color.black
            map
            // The band clears the home indicator only when the stage actually reaches the
            // bottom of the glass — which is full screen, and nothing else. In a letterboxed
            // frame the bar is inside the picture and there is nothing to clear.
            bottomBand(clearance: box.maxY >= glass.height - 0.5 ? insets.bottom : 0)
            // The four frames, over the map and under the transport. Each is opaque and fills
            // the box, which is what lets the one underneath it change (or disappear) without
            // a single frame of the change reaching the video.
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
                ReplayOutroCardView(stats: outroStats, thumbnail: outline,
                                    isWide: framing.isWide(on: glass))
                    .transition(.opacity)
                    .onTapGesture { revealControls() }
            }
            if case .countdown(let count) = stage { countdown(count) }
            if stage == .wrappingUp { wrappingUp }
        }
        .frame(width: box.width, height: box.height)
        // Clipped, and this is load-bearing rather than tidy: MapKit draws to the edge of
        // whatever it is given, and an unclipped map would paint straight over the letterbox
        // the rider is composing against.
        .clipped()
        .position(x: box.midX - insets.leading, y: box.midY - insets.top)
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
    private func bottomBand(clearance: CGFloat) -> some View {
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
                // read a 30× jibe as an impossible one. Rounded rather than truncated: the
                // rate is now solved from a length and lands on 105.7, not on a round number.
                chip("\(Int(pacing.rate.rounded()))×")
            }
            .padding(.horizontal, 14)
            progressHairline
        }
        // A floor under the clearance, and it is MapKit's doing: the "Maps · Legal"
        // attribution is drawn at the bottom of the map view and cannot be moved. On a
        // full-screen replay the home-indicator inset lifted the band clear of it by
        // accident; inside a letterboxed stage there is no inset, and the elapsed chip
        // landed on top of the word "Maps". 22 pt is the attribution's own height.
        .padding(.bottom, 6 + max(clearance, 22))
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
                stage = .clip(await framed(url))
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

    /// Cuts the staged frame out of the full-screen recording, lays the rider's music under it,
    /// or hands back the recording untouched.
    ///
    /// ReplayKit captures the glass, so this is the second half of the framing: the rider
    /// composed against a box (`staged`), and this is where the box becomes the file. It runs
    /// while `.wrappingUp` is still on screen, which is what the "Saving the clip…" spinner is
    /// covering — an export of a forty-second clip is a second or two.
    ///
    /// **Music forces the export even on a full-screen clip.** Full screen used to mean "no
    /// export at all", which is still true when there is nothing to add; a track to mux is a
    /// second reason to re-encode, and then the crop is simply absent from the same pass rather
    /// than being a second one (`ReplayClipCropper.export`).
    ///
    /// **A failure is a fallback, not an error.** The rider has just spent the length of the
    /// clip making it, and there is a perfectly good full-screen recording in his hand; losing
    /// it because a re-encode failed would be the wrong trade every time. So the plain file is
    /// offered with a line saying what it is missing and why.
    private func framed(_ url: URL) async -> URL {
        let wantsCrop = framing != .fullScreen && glassSize.width > 0 && !stageRect.isEmpty
        // Nothing to crop and nothing to add: the recorder's own file is the clip. This is also
        // the safety net — whatever else goes wrong, this path always has a file.
        guard wantsCrop || music != nil else { return url }
        do {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                return url
            }
            var crop: CGRect?
            if wantsCrop {
                // The *displayed* size, transform applied: a portrait capture is stored
                // landscape with a rotation on it, and cropping against the stored size would
                // cut the clip sideways.
                let natural = try await track.load(.naturalSize)
                let preferred = try await track.load(.preferredTransform)
                let displayed = CGRect(origin: .zero, size: natural).applying(preferred).size
                let pixels = CGSize(width: abs(displayed.width), height: abs(displayed.height))
                let wanted = ReplayStage.crop(stage: stageRect, screenPoints: glassSize,
                                              videoPixels: pixels)
                crop = ReplayStage.needsCrop(wanted, videoPixels: pixels) ? wanted : nil
            }
            guard crop != nil || music != nil else { return url }
            let output = url.deletingPathExtension()
                .appendingPathExtension("\(framing.rawValue).mp4")
            let exported = try await ReplayClipCropper.export(url, crop: crop, music: music,
                                                              output: output)
            // A track that turned out to be silent — an empty file, something that is not audio
            // at all — costs the music and not the clip, which is the same trade the crop makes
            // below. The rider is told, because a silent clip he expected to have a song under
            // it is otherwise a mystery.
            if music != nil,
               (try? await AVURLAsset(url: exported).loadTracks(withMediaType: .audio))?.isEmpty
                   != false {
                framingNote = "The music could not be read, so this clip is silent."
            }
            return exported
        } catch {
            let reason = (error as? any LocalizedError)?.errorDescription
                ?? error.localizedDescription
            // One export, so one failure loses whatever was asked of it — and the note has to
            // say which, or the rider is left wondering what he is looking at.
            let lost = [wantsCrop ? "cropped to \(framing.name.lowercased())" : nil,
                        music != nil ? "given its music" : nil].compactMap { $0 }
            framingNote = "The clip could not be \(lost.joined(separator: " or ")) (\(reason)), "
                + "so this is the recording as it was captured."
            return url
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
    /// The session's readable name, which doubles as the place the share message leads with —
    /// `SessionDisplay.title` is the only place-ish string the app has, and it is the one the
    /// clip's own title card already prints.
    let title: String
    /// The afternoon, for the share message's date. The same instant `ShareCardStats.dateLine`
    /// formats on the card, so the two exports of one session are dated identically.
    let startedAt: Date
    /// The session's own zone (`SessionRow.displayZone`) — so the date in the message names
    /// the afternoon the rider had, not the one the phone is currently having.
    let timeZone: TimeZone
    /// Wall seconds actually captured — the run's own measurement, not a probe of the file.
    let wallS: Double
    /// Set when the clip is not the shape that was asked for, and why — see
    /// `ReplayCinemaView.framed`. The rider gets the recording either way; what he must not
    /// get is the wrong shape without being told.
    var note: String?
    let discard: () -> Void
    let done: () -> Void

    /// Built once, in `onAppear`: a player rebuilt in `body` would restart from the first
    /// frame every time the size label or the share sheet caused a redraw.
    @State private var player: AVPlayer?
    @State private var saving = SaveState.idle
    @State private var saveFailure: PhotoLibrarySaver.Failure?

    /// Where the "Save to Photos" button is in its one-way trip.
    ///
    /// `saved` is terminal on purpose. A button that went back to "Save to Photos" after a
    /// second and a half would invite a second tap and a second copy in the camera roll; one
    /// that stays "Saved" is both the confirmation and the reason not to press it again. (A
    /// rider who genuinely wants two copies has the share sheet.)
    private enum SaveState: Equatable {
        case idle, saving, saved
    }

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

                if let note {
                    Label(note, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ShareLink(item: url, subject: Text(title), message: Text(caption)) {
                    Label("Share clip", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                saveButton

                Button(role: .destructive, action: discard) {
                    Label("Discard", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .onAppear {
                if player == nil { player = AVPlayer(url: url) }
                // `.playback` so a clip with music under it is audible with the ring switch
                // set to silent — which is where a phone that has just been out on the water
                // usually is. Without it the preview is mute and the rider concludes the mux
                // failed. The category is claimed here and given back on the way out, so the
                // app never holds the audio session while it is not playing anything.
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .moviePlayback)
                try? session.setActive(true)
            }
            .onDisappear {
                player?.pause()
                try? AVAudioSession.sharedInstance()
                    .setActive(false, options: .notifyOthersOnDeactivation)
            }
            .navigationTitle("Replay clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                }
            }
            .alert("Save to Photos",
                   isPresented: Binding(get: { saveFailure != nil },
                                        set: { if !$0 { saveFailure = nil } }),
                   presenting: saveFailure) { failure in
                // Only where there is something to open. A library error is not a permission
                // problem and sending the rider to Settings for it would be a dead end.
                if failure.isFixableInSettings,
                   let settings = URL(string: UIApplication.openSettingsURLString) {
                    Button("Open Settings") { UIApplication.shared.open(settings) }
                }
                Button("OK", role: .cancel) { saveFailure = nil }
            } message: { failure in
                Text(failure.errorDescription ?? "")
            }
        }
    }

    /// "Save to Photos" — the second thing to do with a clip, and the one the sheet was
    /// missing.
    ///
    /// Secondary to Share by weight, not by importance: sharing is what a clip is *for*, and
    /// the camera roll is where it goes when the rider wants to keep it or post it later from
    /// somewhere else. The system share sheet does carry a "Save Video" of its own, buried
    /// under the app row, which is exactly why this is here — that is a destination in a list,
    /// not a button on a screen.
    @ViewBuilder
    private var saveButton: some View {
        Button {
            Task { await saveToPhotos() }
        } label: {
            Label(saving == .saved ? "Saved to Photos" : "Save to Photos",
                  systemImage: saving == .saved ? "checkmark.circle.fill"
                                                : "square.and.arrow.down")
                .frame(maxWidth: .infinity)
                // The spinner replaces the label rather than sitting beside it, so the button
                // does not change width in the middle of being pressed.
                .opacity(saving == .saving ? 0 : 1)
                .overlay { if saving == .saving { ProgressView() } }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(saving == .saved ? .green : .accentColor)
        .disabled(saving != .idle)
    }

    private func saveToPhotos() async {
        guard saving == .idle else { return }
        saving = .saving
        do {
            try await PhotoLibrarySaver.save(video: url)
            saving = .saved
        } catch let failure as PhotoLibrarySaver.Failure {
            saving = .idle
            saveFailure = failure
        } catch {
            saving = .idle
            saveFailure = .library((error as NSError).localizedDescription)
        }
    }

    /// "Torbole, 30 August 2026 — CleanJibe session clip · cleanjibe.org".
    ///
    /// Composed in the kit (`ShareText`) alongside the FIT's and the card's, so an afternoon
    /// exported three ways is named and dated identically all three times. Shorter than the
    /// FIT's, though, and deliberately: a video is not a file anybody will open in a browser
    /// tool, so it gets the credit without the analyzer pitch.
    private var caption: String {
        ShareText.clipMessage(place: title, startedAt: startedAt, timeZone: timeZone)
    }
}
