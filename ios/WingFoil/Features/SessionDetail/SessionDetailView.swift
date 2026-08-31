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
///   you cannot see. The records live on Map · Speed, as a table, with the figures they
///   annotate (§1.4, and the review's "deliberately not recommended").
struct SessionDetailView: View {
    let sessionID: String
    @Environment(SessionStore.self) private var store

    @State private var detail: SessionDetail?
    @State private var failure: String?
    /// The selected section. `mapSpeed` is what every session opens on, because the figures
    /// are the browsing surface and the block above them has already given the verdict. The
    /// enum, its words and the anchor mapping live in the kit (`SessionSection`) so the
    /// rules are testable and so the web app can use the same four ids.
    @State private var tab = SessionSection.mapSpeed
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
                    // after the title (§1.3).
                    if !detail.divergences.isEmpty {
                        DivergenceBanner(divergences: detail.divergences)
                    }
                    Section {
                        VStack(alignment: .leading, spacing: 20) {
                            body(of: tab, detail: detail)
                            footer(detail)
                        }
                    } header: {
                        switcher
                    }
                } else if let failure {
                    ContentUnavailableView("Could not open this session",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(failure))
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
            // card, "hr" for the HR-cost card, "gear" for the gear card, "replay" for the
            // scrubber). Since the page is tabbed, the anchor also has to *select the tab
            // it lives on* — a scroll to an anchor on an unselected tab reaches nothing.
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
                if let anchor = environment["UI_SCROLL_TO"] {
                    if let home = SessionSection.section(owning: anchor) { tab = home }
                    proxy.scrollTo(anchor, anchor: .top)
                }
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
        case .mapSpeed: mapSpeed(detail)
        case .turns: SessionTurnsSection(detail: detail)
        case .takeoffs: SessionTakeoffSection(detail: detail)
        case .effort: effortTab(detail)
        }
    }

    /// **One instrument, one tab.** The map, its legend, the speed chart, the scrubber they
    /// share and the record table that annotates both. The shared playhead binding and the
    /// `flightFocus` a map tap sets are the contract's "one playhead" and "pairing"
    /// (`presentation.md`), and the only way to keep them visibly true is to keep the two
    /// figures on one screen. Nothing here may be moved to another tab.
    @ViewBuilder
    private func mapSpeed(_ detail: SessionDetail) -> some View {
        if detail.segments.isEmpty {
            noTrackNote
        } else {
            TrackMapView(detail: detail, effort: effort, playhead: $playhead,
                         visibility: store.mapLayers, flightFocus: $flightFocus,
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
        SpeedChartView(detail: detail, effort: effort, playhead: $playhead,
                       visibility: store.mapLayers, flightFocus: flightFocus,
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

    /// What the session cost: the HR card, its fatigue bins, and the kit it was ridden on.
    /// Gear sits here rather than on a tab of its own because a wing and a foil are the
    /// other half of the same question the heart rate answers — how hard was that, and on
    /// what.
    @ViewBuilder
    private func effortTab(_ detail: SessionDetail) -> some View {
        // Silent — no card at all — on a session whose heart rate measured nothing.
        HrCostCardView(detail: detail)
        SessionGearCard(sessionID: sessionID)
            .id("gear")
    }

    @ViewBuilder
    private var header: some View {
        if let row {
            VStack(alignment: .leading, spacing: 6) {
                Text(Fmt.date(row.startDate, zone: row.displayZone))
                    .font(.title3.weight(.semibold))
                if row.isExample { exampleNote }
                if row.rider != nil { riderNote(row) }
                HStack(spacing: 8) {
                    Text(SessionDisplay.badge(row))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(SessionDisplay.badgeColor(row).opacity(0.16), in: .capsule)
                        .foregroundStyle(SessionDisplay.badgeColor(row))
                    Text(Fmt.duration(row.durationS))
                    Text("·")
                    Text(Fmt.km(row.distanceKm))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let detail { WindRow(detail: detail) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    private func footer(_ detail: SessionDetail) -> some View {
        let rate = String(format: "%.1f", detail.analysis.capabilities.sampleRateHz)
        let provenance = "Engine \(detail.analysis.engineVersion) · \(rate) Hz · "
            + "sport \(SessionDisplay.sportLabel(detail.row.sport))"
            + (detail.row.importSource.map { " · via \($0)" } ?? "")
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(SessionDisplay.sourceClassNote(detail.row.sourceClass))
                HelpButton(topic: .sourceClass, size: .caption2)
            }
            Text(provenance)
            if let file = detail.row.originalFilename { Text(file) }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
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
            parts.append("Wind from \(compass(wind.dirDeg)) "
                         + "\(Int(wind.dirDeg.rounded()))° · \(confidence) % confident"
                         + qualifier)
        }
        if let user = detail.windDirUserDeg {
            parts.append("set on watch \(Int(user.rounded()))°")
        }
        return parts.joined(separator: " · ")
    }

    private func compass(_ deg: Double) -> String {
        let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                     "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int(((deg.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360) / 22.5).rounded()) % 16
        return names[index]
    }
}

/// Watch-vs-phone divergence banner (docs/plan.md §5, thresholds in docs/algorithms.md).
/// A standing field-regression alarm on every class-(a) import: the phone recompute is
/// authoritative, so a divergence is a tuning issue to file against the session fixture,
/// not an error the rider has to act on.
private struct DivergenceBanner: View {
    let divergences: [Divergence]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Watch and phone disagree on \(list)")
                        .font(.footnote.weight(.medium))
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(divergences) { d in
                        HStack {
                            Text(d.metric).frame(width: 120, alignment: .leading)
                            Text(d.watch).frame(width: 70, alignment: .trailing)
                            Text("→")
                            Text(d.phone).frame(width: 70, alignment: .trailing)
                            Text(d.delta).foregroundStyle(.orange)
                            Spacer()
                        }
                        .font(.caption2.monospacedDigit())
                    }
                    HStack(spacing: 6) {
                        Text("The phone recompute is authoritative — file this against the "
                             + "session fixture as a tuning issue.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        HelpButton(topic: .divergence)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 12))
    }

    private var list: String {
        let names = divergences.map(\.metric)
        if names.count <= 2 { return names.joined(separator: " and ").lowercased() }
        return names.prefix(2).joined(separator: ", ").lowercased()
            + " and \(names.count - 2) more"
    }
}
