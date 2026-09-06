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
    let sessionID: String
    @Environment(SessionStore.self) private var store

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
    /// Transient like every other zoom (docs/presentation.md, "Pairing").
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

    private var row: SessionRow? { store.session(id: sessionID) }

    private var effort: SessionDetail.RecordEffort? {
        guard let detail, let selectedEffort else { return nil }
        return detail.efforts.first { $0.id == selectedEffort }
    }

    var body: some View {
        ScrollView {
            ScrollViewReader { proxy in
            // `pinnedViews` is what makes the switcher sticky: it stays under the nav bar
            // while a tab's body scrolls past it, so changing subject never means scrolling
            // back up to find the control that changes subject.
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                header
                if let detail {
                    // Permanent, above the switcher, on every tab: the four rows that
                    // answer "was that a good session" (docs/app-ui-review.md §1.1 / §4).
                    KeyMetricsView(metrics: KeyMetrics.make(summary: detail.analysis.summary,
                                                            records: detail.analysis.records))
                        .id("key")
                    // Below the verdict now, not above it. It is a provenance footnote
                    // about one metric, and it was the most prominent element on the screen
                    // after the title (§1.3). One line: the numbers behind it are on Log,
                    // which is where the recording's own facts live, and the banner's job
                    // here is to say there is something to go and read.
                    if !detail.divergences.isEmpty {
                        DivergenceBanner(sessionID: sessionID,
                                         divergences: detail.divergences) {
                            jump(to: "divergence", proxy: proxy)
                        }
                    }
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
                                 + "downloading, or the stored file is damaged — try "
                                 + "importing the session again.")
                            Text(failure)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    ProgressView("Analyzing…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
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
                if let anchor = environment["UI_SCROLL_TO"] { jump(to: anchor, proxy: proxy) }
            }
            #endif
            }
        }
        .navigationTitle(row.map(SessionDisplay.title) ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG && targetEnvironment(simulator)
        .navigationDestination(isPresented: $showFullScreenMap) {
            if let detail {
                FullScreenMapView(detail: detail, effort: effort, playheadT: playhead)
            }
        }
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showShare = true } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(row == nil)
            }
        }
        .sheet(isPresented: $showShare) {
            if let row {
                ShareComposerView(row: row, detail: detail)
            }
        }
        .task(id: sessionID) { await load() }
    }

    private func load() async {
        guard detail == nil, let row else { return }
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
            ForEach(SessionSection.allCases) { Text($0.label).tag($0) }
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
        case .log: SessionLogView(detail: detail, sessionID: sessionID)
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
                Text(Fmt.date(row.startDate, zone: row.displayZone))
                    .font(.title3.weight(.semibold))
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
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let detail { WindRow(detail: detail) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

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
            Text("Times estimated from the track's position — this recording carries no "
                 + "time zone.")
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
            Text("Bundled demo session — \(ExampleSession.place). Not counted in your "
                 + "records or trends.")
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
        Label("This recording has no GPS positions — chart and records only.",
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
            let qualifier = wind.usable ? "" : " (too weak to name turns)"
            parts.append("Wind from \(Fmt.compass(wind.dirDeg)) "
                         + "\(Int(wind.dirDeg.rounded()))° · \(confidence) % confident"
                         + qualifier)
        }
        if let user = detail.windDirUserDeg {
            parts.append("set on watch \(Int(user.rounded()))°")
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
                Text("Watch and phone disagree on \(list)")
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

    private var list: String {
        let names = divergences.map(\.metric)
        if names.count <= 2 { return names.joined(separator: " and ").lowercased() }
        return names.prefix(2).joined(separator: ", ").lowercased()
            + " and \(names.count - 2) more"
    }
}
