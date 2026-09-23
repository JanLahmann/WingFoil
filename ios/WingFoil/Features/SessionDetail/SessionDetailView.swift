import SwiftUI
import WingFoilKit

/// One session, as a permanent verdict over a four-way switcher.
///
/// **Why it is tabbed.** The page was one column of ~3 800 pt — a little over four full
/// phone screens — carrying five unrelated subjects with no way to the fifth except through
/// the other four (`app-ui-review.md` §3.1). A rider who wants to know how his jibes went
/// scrolled past the map, the chart, the replay, four foil tiles and eight record tiles to
/// get there.
///
/// **Why it is tabbed *here*, and not somewhere more obvious.** `presentation.md` "Scrub and
/// zoom" mandates one playhead — the chart scrub position and the map dot are the same
/// timestamp, and moving either moves both — and "Pairing" adds that tapping a flown stretch
/// of track focuses the chart on that flight. Map and chart are therefore one instrument,
/// not two pages, and the tab set floated in the brief (`Overview / Map / Turns / Takeoffs /
/// Records`) breaks the visible half of that link: you tap a segment on Map and the chart it
/// just focused is on another tab. So the split falls between **the figures** — map and
/// chart together, always, on one tab — and **the analysis cards**, which are genuinely five
/// independent subjects (§3.2).
///
/// Two things that look like omissions and are decisions:
///
/// * **There is no Overview tab.** The key-metrics block *is* the overview, and it sits
///   above the switcher on every tab: it is the answer to "was that a good session" and it
///   should never be a page you can navigate away from.
/// * **There is no Records tab.** The record picker's whole purpose is to highlight a window
///   on the map and the chart; a picker on a tab away from the figures highlights something
///   you cannot see. The records live on Ride, as a table, with the figures they annotate
///   (§1.4, and the review's "deliberately not recommended").
///
/// **The four were re-cut on 6 Sep 2026** (Jan) — see `SessionSection` for the reasoning.
/// Takeoffs and Effort were one subject split by sensor, so the HR card came under the
/// takeoff tiles and Effort's name went back to the map legend, which had spent the word
/// first; and Log picked up the four facts about the *recording* that had been living as
/// furniture — the footer under every tab, the wind line's detail, the divergence table
/// behind a banner's disclosure, and the gear card.
struct SessionDetailView: View {
    /// The session the rider tapped. The page can move off it — see `shownID`.
    let sessionID: String
    @Environment(SessionStore.self) private var store

    /// **The session on screen**, once a swipe has moved the page off the one that was
    /// pushed (item 5 of the 18 Sep 2026 round).
    ///
    /// Paging in place rather than pushing: the rider is reading his afternoons, and the
    /// question after "how was that one" is "how was the one before it" — the same reason
    /// the turn page swipes rather than popping (`TurnDetailSheet`). A push per session
    /// would build a stack he then has to unwind, and the back button would lie about
    /// where it goes. Nil until he swipes, so a cold push still draws what it was asked for.
    @State private var shownID: String?
    /// How far the page is drawn from its resting place while a finger is on it. Zero at
    /// rest, which is every moment except the drag itself.
    @State private var dragX: CGFloat = 0
    /// Which way the last page turn went, so the two halves of the slide — the page
    /// leaving and the page arriving — are told apart (`pageTurn`). It outlives the drag
    /// because the transition is read while the animation runs.
    @State private var lastStep = SessionPaging.Step.next
    /// The title editor. Renaming used to live only inside the share composer, which is a
    /// long way to go to fix a name the list is showing wrong (GitHub issue 13).
    @State private var renaming = false
    @State private var titleDraft = ""

    @State private var detail: SessionDetail?
    @State private var failure: String?
    /// The selected section. `ride` is what every session opens on, because the figures
    /// are the browsing surface and the block above them has already given the verdict. The
    /// enum, its words, the anchor mapping and the routing rule live in the kit
    /// (`SessionSection`) so they are testable.
    @State private var tab = SessionSection.ride
    /// Engine window key of the GP3S effort highlighted on the map and chart. Transient by
    /// design (`RecordWindowSelection`): every session opens on the 2 s peak.
    @State private var selectedEffort: String? = RecordWindowSelection.defaultKey
    /// Session-clock seconds under the replay playhead; nil = not scrubbing. Shared by the
    /// scrubber, the chart and the map — that shared binding *is* the map/chart link.
    @State private var playhead: Double?
    /// The flight a tap on the map asked about — the map sets it, the chart frames it.
    /// Transient like every other zoom (docs/presentation/scrub-pairing.md, "Pairing").
    @State private var flightFocus: SessionDetail.FlightFocus?
    /// The speed chart's visible window. Owned here rather than by the chart so a trip to
    /// another tab does not reset it — see `SpeedChartView.zoom`.
    @State private var chartZoom: TimelineWindow?
    /// What the replay says as it plays (`ReplayCommentary`). Derived once when the session
    /// opens rather than in the map's body: playback moves the playhead twenty times a
    /// second and every one of those re-evaluates every view on this page.
    @State private var milestones: [ReplayMilestone] = []
    @State private var showShare = false
    #if DEBUG && targetEnvironment(simulator)
    /// Screenshot hook only (`UI_FULLSCREEN_MAP=1`): `simctl` cannot tap the link.
    @State private var showFullScreenMap = false
    #endif

    /// What the page is drawing, which is the pushed session until a swipe says otherwise.
    private var shown: String { shownID ?? sessionID }

    private var row: SessionRow? { store.session(id: shown) }

    /// **The list's order, as the page inherits it** — the filtered, sorted run the Sessions
    /// tab is showing (`SessionStore.visibleSessionIDs`), so a swipe walks the afternoons in
    /// the order the rider is reading them rather than in the library's own. Falls back to
    /// the whole library, which is what a page reached from Records or from a notification
    /// has behind it.
    private var order: [String] {
        store.visibleSessionIDs.contains(shown) ? store.visibleSessionIDs
                                                : store.sessions.map(\.id)
    }

    private var position: Int? { order.firstIndex(of: shown) }

    private var previousID: String? {
        guard let position, position > 0 else { return nil }
        return order[position - 1]
    }

    private var nextID: String? {
        guard let position, position + 1 < order.count else { return nil }
        return order[position + 1]
    }

    /// **Turns the page**, one step in the list's order, with the slide that says which way
    /// it went. The flick and the `‹ ›` pair both come through here, so the two moves are
    /// the same move and are animated once.
    ///
    /// A step with nothing on the other side of it — the ends of the list — still runs:
    /// the page springs back from wherever the finger left it, which is the answer a
    /// scroll view gives at its own ends.
    private func turn(_ step: SessionPaging.Step) {
        let target = switch step {
        case .next: nextID
        case .previous: previousID
        case .stay: String?.none
        }
        withAnimation(.snappy(duration: 0.28)) {
            dragX = 0
            if let target {
                lastStep = step
                show(target)
            }
        }
    }

    /// The slide itself: the outgoing page leaves by the edge the finger pushed it towards
    /// and the incoming one arrives from the opposite one. Turning back reverses both.
    private var pageTurn: AnyTransition {
        let forward = lastStep != .previous
        return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading),
                           removal: .move(edge: forward ? .leading : .trailing))
    }

    /// Moves the page to another session and forgets everything that was about the old one.
    /// The selected tab deliberately survives: a rider comparing his jibes stays on Turns.
    private func show(_ id: String?) {
        guard let id, id != shown else { return }
        shownID = id
        detail = nil
        failure = nil
        playhead = nil
        flightFocus = nil
        chartZoom = nil
        milestones = []
        selectedEffort = RecordWindowSelection.defaultKey
    }

    private var effort: SessionDetail.RecordEffort? {
        guard let detail, let selectedEffort else { return nil }
        return detail.efforts.first { $0.id == selectedEffort }
    }

    /// **One session's page**, as its own view so that turning to another one can animate.
    ///
    /// It is given `.id(shown)` by the body below, which means SwiftUI builds a second copy
    /// of it for the session being turned to and keeps this one alive while the two slide
    /// past each other. Nothing in here knows about that, and nothing in here changed when
    /// the page learned to slide.
    private var page: some View {
        ScrollView {
            ScrollViewReader { proxy in
            // `pinnedViews` is what makes the switcher sticky: it stays under the nav bar
            // while a tab's body scrolls past it, so changing subject never means scrolling
            // back up to find the control that changes subject.
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                header
                if let row, row.isProvisional {
                    // A card from the watch, with no recording behind it yet. Not an error:
                    // the numbers the watch sent are real, and the page says what happens
                    // next instead of "damaged, import again" (Jan, 14 Sep 2026, the first
                    // card that ever reached his phone).
                    provisionalState(row)
                } else if let detail {
                    // Permanent, above the switcher, on every tab: the four rows that
                    // answer "was that a good session" (docs/app-ui-review.md §1.1 / §4).
                    KeyMetricsView(metrics: detail.keyMetrics)
                        .id("key")
                    // **Why this page's numbers are in nothing else.** One line, directly
                    // under the block it is about, so a rider who wonders where his session
                    // went in the totals reads the answer beside the evidence for it
                    // (docs/presentation/not-a-session-spots.md, "Not a session").
                    if !detail.analysis.summary.isSession {
                        Text(NotASessionNote.line(
                            reason: detail.analysis.summary.notASessionReason,
                            durationS: detail.analysis.summary.durationS,
                            distanceKm: detail.analysis.summary.distanceKm))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // Below the verdict now, not above it. It is a provenance footnote
                    // about one metric, and it was the most prominent element on the screen
                    // after the title (§1.3). One line: the numbers behind it are on Log,
                    // which is where the recording's own facts live, and the banner's job
                    // here is to say there is something to go and read.
                    if !detail.divergences.isEmpty {
                        DivergenceBanner(sessionID: shown,
                                         divergences: detail.divergences) {
                            jump(to: "divergence", proxy: proxy)
                        }
                    }
                    #if TUNING
                    // One line, in the divergence banner's place and its register: a note
                    // about where these numbers came from. Read off the *analysis*, not off
                    // the current setting — a session analysed under tuned thresholds stays
                    // marked until it is re-derived, which is the only honest answer.
                    if let count = TuningStamp.changedCount(detail.analysis.engineVersion) {
                        tunedBanner(count)
                    }
                    #endif
                    Section {
                        VStack(alignment: .leading, spacing: 20) {
                            body(of: tab, detail: detail)
                        }
                    } header: {
                        switcher
                    }
                } else if let failure {
                    // The rider gets a sentence they can act on; the raw error text stays,
                    // smaller and underneath, because it is the only thing that makes a
                    // report about this session actionable — it is just not the message.
                    ContentUnavailableView {
                        Label("Could not open this session",
                              systemImage: "exclamationmark.triangle")
                    } description: {
                        VStack(spacing: 8) {
                            Text("The recording could not be read. It may still be "
                                 + "downloading, or the stored file is damaged. "
                                 + "Import the session again.")
                            Text(failure)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    ProgressView("Analyzing…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
                // With the session in it, so the mail names this afternoon by itself.
                FeedbackFooter(session: row)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
            // One column, a readable measure wide, in the middle of an iPad's glass. The
            // page is a stack of cards and paragraphs and it does not get better by being
            // 1 366 pt across: the key-metrics row would put three numbers a hand's width
            // apart, and the card grids — `GridItem(.adaptive(minimum: 150))` — would lay
            // six tiles in a row and orphan the seventh. The two figures buy their room
            // back in height instead (`figureHeight(… wide:)`).
            .readableColumn()
            #if DEBUG && targetEnvironment(simulator)
            // Headless-driving hook (see LibraryView): `simctl launch` cannot scroll or
            // tap, so `UI_SCROLL_TO=<anchor>` parks the page on a card section for a
            // screenshot ("chart" for the speed chart, "summary" for the record table,
            // "turns" for the turn cards and the filtered list, "takeoff" for the pumping
            // card, "takeoffsMap" / "takeoffList" for the attempt map and its rows, "hr"
            // for the HR-cost card, "gear" for the gear card, "wind" / "recording" /
            // "divergence" for the Log tab's three, "replay" for the scrubber). Since the
            // page is tabbed, the anchor also has to *select the tab it lives on* — a
            // scroll to an anchor on an unselected tab reaches nothing (`jump(to:proxy:)`).
            .onChange(of: detail == nil) {
                guard detail != nil else { return }
                let environment = ProcessInfo.processInfo.environment
                // `UI_PLAYHEAD=0.0…1.0` parks the replay scrubber at a fraction of the
                // session, so the linked chart/map markers are in an automated shot.
                if let fraction = environment["UI_PLAYHEAD"].flatMap(Double.init),
                   let range = detail?.timeRange {
                    playhead = range.lowerBound
                        + (range.upperBound - range.lowerBound) * min(max(fraction, 0), 1)
                }
                if environment["UI_SHEET"] == "share" { showShare = true }
                // `UI_RECORD=best10s` picks a *non-default* record window, which is the
                // only way to photograph the picker's whole point — the glow on a window
                // other than the 2 s peak — since `simctl` cannot tap a card.
                if let key = environment["UI_RECORD"] {
                    selectedEffort = detail?.efforts.contains { $0.id == key } == true
                        ? key : nil
                }
                // `UI_FULLSCREEN_MAP=1` pushes the big map, where the legend chips are the
                // same controls over the same shared model.
                if environment["UI_FULLSCREEN_MAP"] == "1" { showFullScreenMap = true }
                // `UI_OPEN_TURNS=1` used to push a page; the drill-in is the Turns tab now,
                // so it selects that tab instead. `UI_TURN_FILTER` (read there) still
                // engages the two segmented filters for the shot, unchanged.
                if environment["UI_OPEN_TURNS"] == "1" { tab = .turns }
                // `UI_OPEN_FLIGHT_END=<index>` opens one flight end's page. The list of
                // them is on Log, and the sheet is presented from there
                // (`SessionLogView.FlightEndsCard`), so the hook has to select that tab
                // first — a sheet attached to an unselected tab's subtree never appears.
                if environment["UI_OPEN_FLIGHT_END"] != nil { tab = .log }
                if let anchor = environment["UI_SCROLL_TO"] { jump(to: anchor, proxy: proxy) }
                // `UI_EXPORT_REEL=1` renders a session video with no taps at all and
                // leaves it in Documents (`ReelHook`). It is deliberately not
                // `UI_SHEET=reel`: a sheet can be photographed but a video cannot, and
                // what has to be checked here is the file.
                if ReelHook.isRequested, let detail, let row {
                    Task { await ReelHook.run(detail: detail, title: SessionDisplay.title(row),
                                              store: store) }
                }
            }
            #endif
            }
        }
    }

    var body: some View {
        // **The page slides; it does not swap** (Jan, Beta 75). One session is on screen at
        // a time and the outgoing one leaves the way the finger pushed it: drag left and
        // the afternoon on screen goes left while the next one arrives from the right. The
        // `ZStack` is what lets both exist for the third of a second that takes.
        ZStack {
            page
                .id(shown)
                .transition(pageTurn)
        }
        // Mid-drag the whole page rides under the finger (`SessionPaging.follow`), so the
        // flick is a page turn before it is committed — and visibly nothing at all at the
        // ends of the list, where there is no page to turn to.
        .offset(x: dragX)
        // The sliding pages stop at the screen's edges rather than drawing over the bars.
        .clipped()
        .navigationTitle(row.map(SessionDisplay.title) ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        // **A horizontal flick turns the page to the next afternoon.**
        //
        // `simultaneousGesture`, so the vertical scroll and the map's own pan keep every
        // touch they had — and a strict predicate, because the inline map pans horizontally
        // too: a drag counts only when it is flat and mostly sideways
        // (`SessionPaging.isHorizontal`). The `‹ ›` pair beside the date is the same move
        // for a rider who never tries the flick, and the only chrome it costs.
        //
        // Which way it goes is the kit's rule and not a ternary typed here: the finger
        // drags the content, so leftwards brings in the next session in the list's order
        // (`SessionPaging`, pinned by `SessionPagingTests`).
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard SessionPaging.isHorizontal(dx: dx, dy: dy) else {
                        if dragX != 0 { withAnimation(.snappy) { dragX = 0 } }
                        return
                    }
                    dragX = SessionPaging.follow(
                        dx: dx, hasTarget: (dx < 0 ? nextID : previousID) != nil)
                }
                .onEnded { value in
                    let step = SessionPaging.step(
                        dx: value.translation.width, dy: value.translation.height,
                        predictedDx: value.predictedEndTranslation.width)
                    turn(step)
                })
        #if DEBUG && targetEnvironment(simulator)
        .navigationDestination(isPresented: $showFullScreenMap) {
            if let detail {
                FullScreenMapView(detail: detail, effort: effort, playheadT: playhead)
            }
        }
        #endif
        .toolbar {
            // **The name in the bar is the way to change it** (GitHub issue 13). Renaming
            // lived inside the share composer, so a rider whose watch had filed the
            // afternoon under the wrong place had to open a sheet about sharing to fix a
            // name the list was showing him. It is the same `customTitle` either way.
            ToolbarItem(placement: .principal) {
                Button {
                    titleDraft = row.map(SessionDisplay.title) ?? ""
                    renaming = true
                } label: {
                    Text(row.map(SessionDisplay.title) ?? "Session")
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(row == nil)
                .accessibilityHint("Rename this session")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showShare = true } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                // Nothing to draw a card from until the recording is in.
                .disabled(row == nil || row?.isProvisional == true)
            }
        }
        .sheet(isPresented: $showShare) {
            if let row {
                ShareComposerView(row: row, detail: detail)
            }
        }
        .sheet(isPresented: $renaming) {
            if let row { RenameSessionSheet(row: row, draft: $titleDraft) }
        }
        .task(id: shown) {
            Usage.record(.sessionOpened)
            await load()
        }
    }

    /// The preset every word and every hidden pump chip on this page reads from.
    private var discipline: Discipline { row?.analysisDiscipline ?? .wingfoil }

    private func load() async {
        // A provisional row has nothing to load: the card is the whole of it until the
        // recording arrives, and asking the archive for a file it cannot have would only
        // manufacture the failure state.
        guard detail == nil, let row, !row.isProvisional else { return }
        do {
            let loaded = try await store.detail(for: row)
            detail = loaded
            // The commentary needs two things the kit deliberately does not own: a readable
            // name for the place, and the wall-clock time the recording started. Both are
            // the app's (`ShareCardStats.make` draws the same line), so they are handed over
            // here rather than derived from a filename inside the model.
            milestones = ReplayCommentary.make(loaded.analysis, span: loaded.timeRange,
                                               place: SessionDisplay.title(row),
                                               startedAt: row.startDate,
                                               timeZone: row.displayZone)
        } catch {
            failure = "\(error)"
        }
    }

    // MARK: - The card, before the recording

    /// **What the watch sent, while the recording is still on its way.**
    ///
    /// The card's numbers first, because they are the session as the rider remembers it
    /// from the wrist; then the one sentence about how the rest arrives. Every number is
    /// read off the row the card filled (`SessionRow.apply(_ card:)`); a column the card
    /// does not carry is simply not shown, never printed as zero.
    private func provisionalState(_ row: SessionRow) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                provisionalCell("Time", KeyMetrics.duration(row.rateSeconds))
                provisionalCell("Foil", Fmt.pct(row.foilPct))
                if let flights = row.flightCount {
                    provisionalCell("Flights", "\(flights)")
                }
                provisionalCell("Best 2 s", Fmt.kn(row.best2sKn))
            }
            HStack(spacing: 10) {
                OutcomeTally(flewThrough: row.turnsFlewThrough ?? 0,
                             touchdown: row.turnsTouchdown ?? 0,
                             fellIn: row.turnsFellIn ?? 0)
                Text(Fmt.km(row.distanceKm))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ContentUnavailableView {
                Label("From your watch", systemImage: "antenna.radiowaves.left.and.right")
            } description: {
                Text("The watch sent its summary the moment you stopped. The full recording "
                     + "follows once Garmin Connect has synced it. Pull down on Sessions "
                     + "after intervals.icu has the activity. Or share the .fit file into "
                     + "CleanJibe.\n\n"
                     + "Then this page fills with the map, every turn and the records. "
                     + "These numbers are worked out again from the recording.")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func provisionalCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Going to a card

    /// **One way in to any card on the page**, whichever tab it is on.
    ///
    /// A scroll to an anchor on an unselected tab reaches nothing at all — the tab's subtree
    /// does not exist yet — so the switcher has to move first and the scroll has to happen
    /// twice. That was a screenshot hook's private problem until the divergence banner
    /// became a one-line link to the table on Log; it is a general affordance now, and the
    /// routing rule it asks (`SessionSection.tabChange(for:current:)`) is the kit's so a
    /// test can hold it.
    ///
    /// Two beats, not one: selecting the tab only *schedules* its subtree, and on the same
    /// turn of the runloop `scrollTo` silently reaches nothing — which is how `turnList` and
    /// `tally` were once quietly unphotographable. Scroll now (for an anchor already on
    /// screen) and again once the switch has laid out.
    private func jump(to anchor: String, proxy: ScrollViewProxy) {
        if let home = SessionSection.tabChange(for: anchor, current: tab) { tab = home }
        proxy.scrollTo(anchor, anchor: .top)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(.snappy) { proxy.scrollTo(anchor, anchor: .top) }
        }
    }

    // MARK: - The switcher and the four bodies

    /// Sticky, and full-bleed against the scroll behind it — a segmented control floating
    /// on a transparent strip over scrolling cards is unreadable the moment a card passes
    /// under it.
    private var switcher: some View {
        Picker("Section", selection: $tab) {
            // The tab's word in this session's discipline: a windsurfer does not take
            // off, he gets planing (docs/presentation/labels.md, "Discipline lexicon"). Every
            // other segment is the same word on either rig.
            ForEach(SessionSection.allCases) { Text($0.label(discipline)).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityLabel("Session section")
    }

    @ViewBuilder
    private func body(of tab: SessionSection, detail: SessionDetail) -> some View {
        switch tab {
        case .ride: ride(detail)
        case .turns: SessionTurnsSection(detail: detail)
        case .takeoffs: takeoffs(detail)
        case .log: SessionLogView(detail: detail, sessionID: shown)
        }
    }

    /// **One instrument, one tab.** The map, its legend, the speed chart, the scrubber they
    /// share and the record table that annotates both. The shared playhead binding and the
    /// `flightFocus` a map tap sets are the contract's "one playhead" and "pairing"
    /// (`presentation.md`), and the only way to keep them visibly true is to keep the two
    /// figures on one screen. Nothing here may be moved to another tab.
    @ViewBuilder
    private func ride(_ detail: SessionDetail) -> some View {
        if detail.segments.isEmpty {
            noTrackNote
        } else {
            // The map, its controls and the way to a bigger one are one block, at the
            // block's own spacing rather than the page's: with the layer chips collapsed
            // (`MapLegendView`) the point of the change is that the chart is the next thing
            // on the screen, and three 20 pt gaps in a row would spend the space the chips
            // just gave back.
            VStack(alignment: .leading, spacing: 6) {
                TrackMapView(detail: detail, effort: effort, playhead: $playhead,
                             visibility: store.mapLayers(for: .ride),
                             mapStyle: store.mapStyle,
                             flightFocus: $flightFocus,
                             // The toggle on the scrubber row is one store flag away, so
                             // switching the commentary off is an empty list rather than a
                             // second condition inside the map.
                             milestones: store.replayCommentary ? milestones : [])
                NavigationLink {
                    FullScreenMapView(detail: detail, effort: effort, playheadT: playhead)
                } label: {
                    Label("Open map full screen", systemImage: "map")
                        .font(.footnote)
                }
            }
        }
        SpeedChartView(detail: detail, effort: effort, playhead: $playhead,
                       visibility: store.mapLayers(for: .ride), flightFocus: flightFocus,
                       zoom: $chartZoom)
            .id("chart")
        // The same filtered list the map is given, and for the same reason: the scrubber
        // owns the commentary toggle, and the cinema replay it can launch has to caption —
        // and slow down for — exactly the lines the inline map would have shown.
        ReplayScrubber(detail: detail, playhead: $playhead,
                       milestones: store.replayCommentary ? milestones : [])
            .id("replay")
        SessionFoilGrid(detail: detail)
        SessionRecordsTable(detail: detail, selectedEffort: $selectedEffort)
    }

    /// **Getting up, in full**: the tiles, the attempts on the water, and what they cost.
    ///
    /// Takeoffs and the old Effort tab were one subject split by which sensor saw it — the
    /// accelerometer counted the attempts, the optical heart rate priced them — and "how many
    /// did I have to pump for" and "what did the pumping cost" are the same question asked
    /// twice. They are one tab now, in the order the question is asked: how it went, where it
    /// happened, what it took out of you.
    ///
    /// The HR card sits *after* the map and list rather than immediately under the tiles,
    /// because the map and the list are the tiles' own drill-in — exactly the shape the Turns
    /// tab has — and the cost is the closing note on all of it. It is silent, no card at all,
    /// on a session whose heart rate measured nothing.
    @ViewBuilder
    private func takeoffs(_ detail: SessionDetail) -> some View {
        SessionTakeoffSection(detail: detail)
        if !detail.takeoffMarks.isEmpty {
            Divider()
            TakeoffsAnalysisView(detail: detail)
        }
        HrCostCardView(detail: detail)
    }

    @ViewBuilder
    private var header: some View {
        if let row {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(Fmt.date(row.startDate, zone: row.displayZone))
                        .font(.title3.weight(.semibold))
                    Spacer(minLength: 8)
                    // The flick, for a rider who has not found the flick. Two glyphs and no
                    // words: the arrows are beside a date, and what is on the other side of
                    // a date needs no label.
                    stepButton("chevron.left", .previous, to: previousID,
                               reads: "Previous session")
                    stepButton("chevron.right", .next, to: nextID, reads: "Next session")
                }
                // **Where this recording came from**, under the date and nowhere else on
                // this tab. It was on the Log tab only, four taps from the question — and
                // "is this the one my watch recorded, or the copy Strava has" is asked
                // while looking at the numbers, not while auditing the file.
                if let source = SessionProvenance.line(importSource: row.importSource) {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if row.zoneIsEstimated { estimatedClockNote }
                if row.isExample { exampleNote }
                if row.rider != nil { riderNote(row) }
                // The badge alone. Duration and distance used to follow it and were the
                // first two cells of the key-metrics block eight points lower — the same
                // two numbers twice on one screen (Jan, 6 Sep 2026). The block is the
                // contract the card mirrors, so the block keeps them and the header does
                // not; the library row still carries both for the list.
                HStack(spacing: 8) {
                    Text(SessionDisplay.badge(row))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(SessionDisplay.badgeColor(row).opacity(0.16), in: .capsule)
                        .foregroundStyle(SessionDisplay.badgeColor(row))
                    // Beside the discipline badge and never instead of it: the badge says
                    // what the *recording* is, this says how it is being read and that the
                    // reading is not one anybody has checked yet.
                    if let chip = row.analysisDiscipline.lexicon.chip {
                        Text(chip)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.orange.opacity(0.16), in: .capsule)
                            .foregroundStyle(.orange)
                    }
                    #if TUNING
                    // Beside the discipline badge, because it is the same kind of fact: what
                    // this session *is*, before any of its numbers are read.
                    if let count = TuningStamp.changedCount(row.engineVersion ?? "") {
                        TunedChip(count: count, compact: true)
                    }
                    #endif
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let detail { WindRow(detail: detail) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One step along the list, greyed at the ends rather than absent: a control that
    /// vanishes at the last session is a control a rider stops trusting (pattern G).
    private func stepButton(_ symbol: String, _ step: SessionPaging.Step, to id: String?,
                            reads: String) -> some View {
        // Through `turn` like the flick, so the arrow slides the page the same way the
        // finger does. A rider who uses both must not see two different animations.
        Button { turn(step) } label: {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(id == nil ? AnyShapeStyle(.tertiary)
                                           : AnyShapeStyle(Color.accentColor))
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(id == nil)
        .accessibilityLabel(reads)
    }

    #if TUNING
    /// The tuned-thresholds line, in the divergence banner's slot and its voice: one sentence
    /// about the provenance of every number below it, and where to go and change it.
    ///
    /// Not dismissible, unlike the divergence banner. A divergence is a note about two sources
    /// disagreeing and the reader can decide he has read it; this is a statement that the page
    /// is not measuring by the published contract, and it goes away by re-analysing with the
    /// defaults, not by being told to.
    private func tunedBanner(_ count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.secondary)
            let noun = count == 1 ? " tuned threshold · " : " tuned thresholds · "
            Text("Analysed with " + String(count) + noun + "Settings → Tuning")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
    #endif

    /// Said under the date when the session's clock was **guessed** — the longitude rung of
    /// the offset ladder (`SessionRow.zoneIsEstimated`, engine 0.9.1).
    ///
    /// Every time on this page is drawn in `row.displayZone`, and for a recording that
    /// stated its own offset that zone is a fact. For one that did not — a GPX, almost
    /// always — it is `round(lon / 15°)` hours: the *solar* offset, an hour out under DST,
    /// which is most of a wingfoil season in Europe. The times are still far better than
    /// the reader's own zone, so the page keeps showing them; what it may not do is let
    /// them read as the clock the rider was actually looking at.
    ///
    /// Shown only in that one case. A session whose watch wrote the offset down gets no
    /// caption at all: a reassurance printed on every page is noise, and noise is what a
    /// reader learns to skip past on the one page where it says something.
    private var estimatedClockNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.badge.questionmark")
                .foregroundStyle(.secondary)
            Text("Times estimated from the track's position. "
                 + "This recording has no time zone.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Said once, at the top, where the reader starts: this page is a demonstration.
    /// Without it the numbers below are indistinguishable from the rider's own — which is
    /// exactly the confusion the badge exists to prevent.
    private var exampleNote: some View {
        HStack(spacing: 8) {
            ExampleBadge(font: .caption)
            Text("Bundled demo session. " + ExampleSession.place
                 + ". Not counted in your records or trends.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HelpButton(topic: .exampleSession, size: .caption2)
        }
    }

    /// Said at the top, beside the name, for the same reason the example note is: the
    /// numbers below are somebody else's, and every one of them looks exactly like the
    /// rider's own. The page analyses the session in full — that is the point of being
    /// sent it — it just does not count.
    @ViewBuilder
    private func riderNote(_ row: SessionRow) -> some View {
        if let rider = row.rider, let note = SessionDisplay.riderNote(row) {
            HStack(spacing: 8) {
                RiderBadge(name: rider, font: .caption)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noTrackNote: some View {
        Label("This recording has no GPS positions. Chart and records only.",
              systemImage: "location.slash")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // The three-line provenance footer that used to close every tab is the Log tab's
    // `Recording` card now (`SessionLogView`). It said the same sentence about source class,
    // the same engine version and the same filename under all four sections of every session
    // forever, which is a fact about the recording filed as page furniture.
}

/// The estimated wind axis, plus the rider's own value from session dev field 39 when the
/// watch wrote one. Below `windMinConfidence` the estimate is shown but explicitly hedged —
/// that is exactly the case where turns stay unnamed rather than being called tacks/jibes.
private struct WindRow: View {
    let detail: SessionDetail

    var body: some View {
        if detail.analysis.wind != nil || detail.windDirUserDeg != nil {
            HStack(spacing: 8) {
                Image(systemName: "wind")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HelpButton(topic: .windAxis)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var text: String {
        var parts: [String] = []
        if let wind = detail.analysis.wind {
            let confidence = Int((wind.confidence * 100).rounded())
            let qualifier = wind.usable ? "" : " · too weak to name turns"
            let bearing = Fmt.compass(wind.dirDeg) + " "
                + String(Int(wind.dirDeg.rounded())) + "°"
            parts.append("Wind from " + bearing + " · " + String(confidence)
                         + " % confident" + qualifier)
        }
        if let user = detail.windDirUserDeg {
            parts.append("set on watch " + String(Int(user.rounded())) + "°")
        }
        return parts.joined(separator: " · ")
    }

}

/// Watch-vs-phone divergence banner (docs/plan.md §5, thresholds in docs/algorithms.md).
/// A standing field-regression signal on every class-(a) import: the phone recompute is
/// authoritative, so a divergence is a note about where a number came from, not an error the
/// rider has to act on — which is why the text says so in the rider's words and why the
/// banner can be sent away. Dismissal is per session and per *divergence*
/// (`DivergenceDismissal`): a later re-analysis that says something different comes back.
///
/// **One line, and a way to the numbers** (6 Sep 2026). It used to carry its own disclosure:
/// tapping it unfolded a four-column table of metric / watch / phone / delta directly under
/// the key-metrics block, which put the most technical thing on the page in the second most
/// prominent place on it. The table is on the Log tab now, with the recording's other facts,
/// and the banner does what a banner is for — it says there is something, and it takes you
/// there. The tap is the whole row, and the chevron points the way rather than down.
private struct DivergenceBanner: View {
    let sessionID: String
    let divergences: [Divergence]
    /// Selects Log and scrolls to the table. Owned by the page, because switching tabs is
    /// the page's business and a banner that knew about the switcher would be a second
    /// router (`SessionDetailView.jump(to:proxy:)`).
    let open: () -> Void
    @AppStorage(DivergenceDismissal.defaultsKey) private var dismissedRaw = ""

    /// The store as an array. `@AppStorage` cannot hold `[String]`, so the fingerprints ride
    /// in one newline-joined string — they are hex and a session id, so neither can contain
    /// the separator.
    private var dismissed: [String] {
        dismissedRaw.split(separator: "\n").map(String.init)
    }

    private var isDismissed: Bool {
        DivergenceDismissal.isDismissed(sessionID: sessionID, divergences: divergences,
                                        dismissed: dismissed)
    }

    var body: some View {
        if !isDismissed { banner }
    }

    private var banner: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(DivergenceText.banner(divergences))
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    // Room for the dismiss X, which floats over the trailing corner.
                    .padding(.trailing, 12)
            }
            .foregroundStyle(.orange)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the watch-versus-phone table on the Log section")
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 12))
        .overlay(alignment: .topTrailing) { dismissButton }
    }

    /// The X. Deliberately quiet — tertiary, no label — because it is an escape hatch on a
    /// footnote, not one of the two things the banner is for.
    private var dismissButton: some View {
        Button {
            let next = DivergenceDismissal.dismissing(sessionID: sessionID,
                                                      divergences: divergences,
                                                      in: dismissed)
            dismissedRaw = next.joined(separator: "\n")
        } label: {
            Image(systemName: "xmark")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(6)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide this note")
        .offset(x: 6, y: 4)
    }

}
