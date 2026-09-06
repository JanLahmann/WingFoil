import CoreLocation
import MapKit
import SwiftUI
import WingFoilKit

/// Track drawn as segmented polylines coloured by phase (flying vs everything else), with
/// the maneuver/flight-end outcomes marked and one GP3S effort highlighted.
///
/// **The inline map pans and zooms** (6 Sep 2026). It used to take no gestures at all so
/// that a drag anywhere on the page scrolled it, which meant the one thing a rider wants to
/// do with a two-kilometre track on a 260 pt figure — get closer to the corner he jibed at —
/// cost a trip to the full-screen map and back. The trade is deliberate and known: a drag
/// that starts on the map moves the map, and the page scrolls from anywhere else on it.
/// Rotate and pitch stay off, because the drawing is a plan view of a plane of water and a
/// tilted one answers nothing. "Open map full screen" stays where it was.
///
/// The map is the second handle on the replay playhead: tapping near the track moves it,
/// and the dot it draws is the same instant the chart and the readout show.
struct TrackMapView: View {
    let detail: SessionDetail
    /// The GP3S effort whose window is glowing on the track, if any.
    let effort: SessionDetail.RecordEffort?
    @Binding var playhead: Double?
    /// Which categories the legend chips are currently showing. Passed in rather than read
    /// here so the drawing stays a pure function of it.
    let visibility: MapLayerVisibility
    /// What the map is drawn on. Passed in for the same reason `visibility` is.
    let mapStyle: MapStyleChoice
    /// The flight the chart is framing, when a flying segment has been tapped. Owned by the
    /// page so the map and the chart are the same tap (docs/presentation.md, "Pairing").
    @Binding var flightFocus: SessionDetail.FlightFocus?
    /// The replay's commentary track (`ReplayCommentary`), or empty when the rider has the
    /// commentary switched off. Passed in rather than derived here for the same reason
    /// `visibility` is: the drawing stays a pure function of what it is given, and the page
    /// owns the one preference both the scrubber's toggle and this caption answer to.
    var milestones: [ReplayMilestone] = []

    /// Tap-only: nothing about the pairing renders until something is tapped.
    @State private var callout: SessionDetail.Callout?
    /// The commentary line on screen right now, and nil the rest of the time — see
    /// `commentaryDwellS`.
    @State private var comment: ReplayMilestone?
    /// Bumped on every flight tap; see `SessionDetail.FlightFocus`.
    @State private var focusTick = 0
    /// The turn whose detail sheet the callout's "Details" affordance opened.
    @State private var openedTurn: TurnDetailRequest?

    /// Direction chevrons for the camera as it stands. State rather than a computed value:
    /// the spacing is measured in screen points, so it is a function of the camera and has
    /// to be rebuilt when the camera moves (see `DirectionField`).
    @State private var direction = DirectionField()

    /// Where the camera is *now*, once the rider has moved it. The tap tolerances are metres
    /// per point, so they are a function of the visible span rather than of the span the map
    /// opened on — read off the initial region until the camera first settles.
    @State private var visibleRegion: MKCoordinateRegion?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MapReader { proxy in
                Map(initialPosition: .region(detail.initialRegion),
                    interactionModes: [.pan, .zoom]) {
                    TrackContent(detail: detail, effort: effort,
                                 visibility: visibility, style: mapStyle,
                                 playhead: playhead.flatMap(detail.moment),
                                 direction: direction)
                }
                .mapStyle(mapStyle.mapStyle)
                .figureHeight(regular: 260, compact: 190)
                .clipShape(.rect(cornerRadius: 14))
                .onMapCameraChange(frequency: .onEnd) { context in
                    visibleRegion = context.region
                    direction.camera(moved: context, detail: detail)
                }
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    direction.resized(to: size, detail: detail)
                }
                // A tap still means exactly one thing — "show me this point" — and it is
                // resolved against the camera as it stands, so it keeps meaning it after a
                // pan or a zoom. A drag is the map's.
                .onTapGesture { location in
                    guard let coordinate = proxy.convert(location, from: .local) else { return }
                    tapped(coordinate)
                }
            }
            // Above the tap callout, immediately under the map: the commentary is about what
            // the dot is doing *now*, so it belongs against the picture, and a caption that
            // jumped below a card the rider happens to have open would move as they watch.
            if let comment {
                ReplayCommentaryBubble(milestone: comment)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let callout {
                TrackCalloutCard(callout: callout,
                                 open: callout.turnIndex.map { index in
                                     { openedTurn = TurnDetailRequest(id: index) }
                                 }) { self.callout = nil }
            }
            // The chips, and their `?`. The caption that used to sit under them ("Tap the
            // track to move the replay playhead — on a mark or a flight for what it was")
            // is the last paragraph of the `mapLegend` help topic now: it was one of the
            // three the review measured at ~115 pt above the fold (§1.2), and it said the
            // same thing on every visit to every session forever.
            MapLegendView(detail: detail, effort: effort)
        }
        // One caption at a time, and only for as long as it is news.
        //
        // The dwell is *wall clock*, which is what "two and a half seconds of playback"
        // means at every replay speed: at 60× a line has 150 s of session to itself and at
        // 10× only 25, and both are the same two and a half seconds of a rider watching.
        // Keying the task on the milestone's id is what makes the replacement instant when
        // two lines fall close together — the pending dismissal is cancelled with the task.
        .task(id: crossedMilestone?.id) {
            guard let crossed = crossedMilestone else {
                // Nothing passed yet, no playhead, or the rider switched the commentary off
                // mid-replay — all three mean "stop talking", and none of them is an error.
                withAnimation(.easeOut(duration: 0.3)) { comment = nil }
                return
            }
            withAnimation(.snappy(duration: 0.2)) { comment = crossed }
            try? await Task.sleep(for: .seconds(Self.commentaryDwellS))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { comment = nil }
        }
        .sheet(item: $openedTurn) { request in
            TurnDetailSheet(detail: detail, start: request.id)
        }
        #if DEBUG && targetEnvironment(simulator)
        .onAppear(perform: stageCalloutForScreenshot)
        #endif
    }

    /// How long a line stays up. Long enough to read a short sentence, short enough that the
    /// next jibe is not commentated over the last one.
    private static let commentaryDwellS = 2.5

    /// The line the playhead has most recently passed. Nil with no playhead at all, so a
    /// session that was opened and not scrubbed says nothing.
    private var crossedMilestone: ReplayMilestone? {
        guard let playhead, !milestones.isEmpty else { return nil }
        return ReplayCommentary.current(at: playhead, in: milestones)
    }

    /// One tap, three answers, in order of how specific they are.
    ///
    /// A tap that lands on a *mark* means that mark — the tolerance is tight, so it takes
    /// aim rather than a stray press near it. Otherwise the tap moves the playhead, which is
    /// what the caption promises; and when it landed on a stretch of *flown* track it also
    /// says which flight that was and frames the flight in the chart. A tap nowhere near the
    /// track is ignored rather than snapping the playhead to some unrelated corner of the
    /// session. Both tolerances scale with how much water the map is showing — the span the
    /// camera has *now*, not the one it opened on, which is what keeps them a fingertip after
    /// the rider has zoomed into one jibe.
    private func tapped(_ coordinate: CLLocationCoordinate2D) {
        let spanM = (visibleRegion ?? detail.region).span.latitudeDelta * 110_540
        if let mark = detail.mark(nearLat: coordinate.latitude, lon: coordinate.longitude,
                                  toleranceM: max(12, spanM * 0.025)) {
            callout = mark
            playhead = mark.t
            return
        }
        guard let t = detail.time(nearLat: coordinate.latitude, lon: coordinate.longitude,
                                  toleranceM: max(25, spanM * 0.06)) else { return }
        playhead = t
        // Off the foil a tap is a scrub and nothing more: there is no flight to name, and a
        // callout that said so would be noise on every second press.
        if let flight = detail.flightCallout(at: t) {
            callout = flight
            focus(on: flight)
        } else {
            callout = nil
        }
    }

    /// Ask the chart to frame the flight this callout is about.
    private func focus(on callout: SessionDetail.Callout) {
        guard let span = callout.focus else { return }
        focusTick += 1
        flightFocus = SessionDetail.FlightFocus(span: span, tick: focusTick)
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Screenshot hook, same family as `UI_HIDE_LAYERS`: the pairing is tap-only and
    /// `simctl` has no fingers, so `UI_MAP_CALLOUT=takeoff|failed|end|flight` opens the
    /// first callout of that kind. Staging only — it opens the same card a tap opens.
    private func stageCalloutForScreenshot() {
        guard let kind = ProcessInfo.processInfo.environment["UI_MAP_CALLOUT"] else { return }
        switch kind {
        case "takeoff", "failed":
            let wantFailed = kind == "failed"
            guard let mark = detail.takeoffMarks.first(where: { $0.isFailed == wantFailed })
            else { return }
            callout = SessionDetail.Callout(id: "takeoff-\(mark.id)", title: mark.title,
                                            detail: mark.detail, pairing: mark.pairing,
                                            t: mark.t)
            playhead = mark.t
        case "end":
            guard let marker = detail.markers.first(where: { $0.pairing != nil }) else { return }
            callout = SessionDetail.Callout(id: "marker-\(marker.id)", title: marker.title,
                                            detail: marker.detail, pairing: marker.pairing,
                                            t: marker.t)
            playhead = marker.t
        case "flight":
            guard let flight = detail.pairings.first else { return }
            let middle = (flight.startTs + flight.endTs) / 2
            callout = detail.flightCallout(at: middle)
            playhead = middle
            if let callout { focus(on: callout) }
        default: return
        }
    }
    #endif
}

/// The tap-only callout, under the map rather than over it: the answer to "what is this?"
/// must not cover the thing that was tapped, and a card that stays put while the rider looks
/// back at the track beats a popover they have to dismiss to see anything.
private struct TrackCalloutCard: View {
    let callout: SessionDetail.Callout
    /// Opens the turn detail sheet. nil on everything that is not a counted turn — a takeoff,
    /// a splash, a flight, a course change — which is what makes the affordance appear only
    /// where there is something to drill into.
    var open: (() -> Void)?
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(callout.title).font(.footnote.weight(.semibold))
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            Text(callout.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
            // The line this whole feature is for. Absent — not blank — on a mark that is
            // not a flight boundary.
            if let pairing = callout.pairing {
                Text(pairing)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("pairing-line")
            }
            if open != nil {
                Text("Details ›")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("turn-details-link")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 10))
        // The whole card is the target, not just the two words: the card is already the
        // answer to "what is this", and "show me more of it" is the same question asked
        // harder. The affordance is there so the tap is discoverable, not so it is the only
        // place that takes one.
        .contentShape(.rect)
        .onTapGesture { open?() }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Turn details") { open?() }
    }
}

struct FullScreenMapView: View {
    let detail: SessionDetail
    let effort: SessionDetail.RecordEffort?
    var playheadT: Double?

    /// Read here rather than passed in: this view is pushed, so it has to observe the
    /// shared model itself to redraw when a chip is tapped *on this screen*.
    @Environment(SessionStore.self) private var store

    @State private var direction = DirectionField()

    var body: some View {
        Map(initialPosition: .region(detail.initialRegion)) {
            TrackContent(detail: detail, effort: effort, visibility: store.mapLayers,
                         style: store.mapStyle,
                         playhead: playheadT.flatMap(detail.moment),
                         direction: direction)
        }
        // The same ground as every other map, points of interest included: this screen used to
        // be the one place they were drawn, which made the big map a slightly different map
        // rather than a bigger one.
        .mapStyle(store.mapStyle.mapStyle)
        // The big map pans, zooms *and rotates*, and all three change the answer: how far
        // apart the chevrons should be, which of them are on screen, and which way "north"
        // points on the glyph.
        .onMapCameraChange(frequency: .onEnd) { context in
            direction.camera(moved: context, detail: detail)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            direction.resized(to: size, detail: detail)
        }
        .navigationTitle(SessionDisplay.title(detail.row))
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .bottom)
        // The same chips, over the same model: filtering the big map is exactly where a
        // rider wants it, and a second copy of the state would be the way to make the two
        // maps disagree.
        .safeAreaInset(edge: .bottom) {
            MapLegendView(detail: detail, effort: effort, compact: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial)
        }
    }
}

/// Shared map content so the inline, full-screen and cinema maps never drift apart.
///
/// Internal rather than private because `ReplayCinemaView` is the third caller: the frame a
/// clip is recorded from has to be the same track, the same marks and the same playhead dot a
/// rider sees on this page, or the video is of an app nobody has.
struct TrackContent: MapContent {
    let detail: SessionDetail
    let effort: SessionDetail.RecordEffort?
    let visibility: MapLayerVisibility
    /// What the ground is. The drawing reads exactly one thing off it — whether the ground is
    /// photography, and therefore whether every stroke and mark needs its dark outer edge
    /// (`TrackHalo`). The phase inks themselves never change: they are the contract.
    var style: MapStyleChoice = .standard
    let playhead: SessionDetail.TimelinePoint?
    let direction: DirectionField

    /// One flag, read here so the four map surfaces cannot disagree about it.
    private var halo: Bool { style.isImagery }

    var body: some MapContent {
        // The halo is a **second pass over the whole track**, drawn before any of it: a
        // per-segment outline would be overdrawn by the next segment's line at every join,
        // which shows up as a dark tick every few hundred metres. Under everything, so nothing
        // above it is dimmed by it.
        if halo {
            ForEach(detail.segments) { segment in
                let line = visibility.lineStyle(flying: segment.flying)
                MapPolyline(coordinates: segment.points.map(Self.coordinate))
                    .stroke(TrackHalo.ink,
                            style: StrokeStyle(lineWidth: TrackHalo.width(under: Self.width(line)),
                                               lineCap: .round, lineJoin: .round))
            }
        }
        ForEach(detail.segments) { segment in
            let line = visibility.lineStyle(flying: segment.flying)
            MapPolyline(coordinates: segment.points.map(Self.coordinate))
                .stroke(Self.color(line, on: style),
                        style: StrokeStyle(lineWidth: Self.width(line),
                                           lineCap: .round, lineJoin: .round))
        }
        // Under the effort glow and under the markers: a pumping attempt is context for
        // the takeoff (or the failure) that ends it, not a thing to read on its own.
        if visibility.isVisible(.pumping) {
            // An attempt the GPS had no fix for is counted by the legend and drawn by
            // nobody: a one-point polyline is not a stretch of water.
            ForEach(detail.pumpSpans.filter { $0.points.count >= 2 }) { span in
                MapPolyline(coordinates: span.points.map(Self.coordinate))
                    .stroke(EventMarkerStyle.pumping.opacity(0.75),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round,
                                               lineJoin: .round))
            }
        }
        // Above the route, below everything that marks an *event*: the chevrons are meant to
        // be read as a property of the line — which way it goes — not as things that happened.
        if visibility.isVisible(.direction) {
            ForEach(direction.chevrons) { chevron in
                Annotation("", coordinate: Self.coordinate(chevron.lat, chevron.lon),
                           anchor: .center) {
                    TrackHalo.around(
                        DirectionChevron(bearingDeg: chevron.bearingDeg - direction.headingDeg,
                                         style: visibility.lineStyle(flying: chevron.flying),
                                         ground: style),
                        on: style)
                }
                .annotationTitles(.hidden)
            }
        }
        // The record effort glows over the phase colouring: provenance the engine already
        // computed (`records.windows`), so the rider can see *where* the best run happened.
        if let effort, effort.points.count >= 2, visibility.isVisible(.effort) {
            MapPolyline(coordinates: effort.points.map(Self.coordinate))
                .stroke(DesignTokens.Effort.window,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        }
        if visibility.isVisible(.takeoff) {
            ForEach(detail.takeoffMarks) { mark in
                Annotation("", coordinate: Self.coordinate(mark.lat, mark.lon),
                           anchor: .center) {
                    TrackHalo.around(EventMarkerStyle.takeoffMark(mark), on: style)
                        .accessibilityLabel("\(mark.title), \(mark.detail)")
                }
                .annotationTitles(.hidden)
            }
        }
        if visibility.isVisible(.splash) {
            ForEach(detail.splashMarks) { mark in
                Annotation("", coordinate: Self.coordinate(mark.lat, mark.lon),
                           anchor: .center) {
                    TrackHalo.around(EventMarkerStyle.splashMark(), on: style)
                        .accessibilityLabel("\(mark.title), \(mark.detail)")
                }
                .annotationTitles(.hidden)
            }
        }
        ForEach(detail.visibleMarkers(visibility)) { marker in
            Annotation("", coordinate: Self.coordinate(marker.lat, marker.lon),
                       anchor: .center) {
                TrackHalo.around(EventMarkerStyle.dot(marker), on: style)
                    .accessibilityLabel("\(marker.title), \(marker.detail)")
            }
            .annotationTitles(.hidden)
        }
        // Drawn last so it sits above the outcome dots — it is the thing being moved.
        if let playhead, let lat = playhead.lat, let lon = playhead.lon {
            Annotation("", coordinate: Self.coordinate(lat, lon), anchor: .center) {
                TrackHalo.around(PlayheadDot(flying: playhead.flying), on: style)
                    .accessibilityLabel(String(format: "Replay position, %.1f knots",
                                               playhead.kn))
            }
            .annotationTitles(.hidden)
        }
    }

    /// A hidden *line* category keeps its route as a thin neutral line: the chips filter
    /// what the colours claim, not where the rider went. Losing the track to a legend tap
    /// would be a much worse surprise than an unwanted tint.
    ///
    /// Foil-teal is the same teal on every ground — it is the contract. The other two are
    /// **ink**, not hue, so over photography they resolve to the light end rather than the
    /// dark one; see `TrackHalo.ink`.
    private static func color(_ line: TrackLineStyle, on style: MapStyleChoice) -> Color {
        switch line {
        case .flying: return DesignTokens.Phase.flying
        case .offFoil:
            return TrackHalo.ink(DesignTokens.Phase.offFoil, on: style,
                                 opacity: 0.65, overImagery: 0.85)
        case .neutral:
            return TrackHalo.ink(DesignTokens.Phase.offFoil, on: style,
                                 opacity: 0.3, overImagery: 0.45)
        }
    }

    private static func width(_ style: TrackLineStyle) -> CGFloat {
        switch style {
        case .flying: return 4
        case .offFoil: return 2
        case .neutral: return 1.5
        }
    }

    private static func coordinate(_ point: SessionDetail.Point) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
    }

    private static func coordinate(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

/// One direction mark. Small, semi-transparent and tinted like the water under it, because
/// it has to lose every contest with the event dots: an arrow is texture on the line, and a
/// touchdown is news.
///
/// Rotation is course *minus the camera's heading*, so it keeps pointing where he was going
/// after the rider spins the big map. Hidden from VoiceOver on purpose — a hundred elements
/// reading "chevron" is noise, and the legend chip is where the layer is named.
private struct DirectionChevron: View {
    let bearingDeg: Double
    let style: TrackLineStyle
    /// What the arrow is drawn on. The chevron is pure ink (`DesignTokens.Direction.ink` is
    /// `Color.primary`), which is the one thing a photograph turns invisible — see
    /// `TrackHalo.ink`.
    var ground: MapStyleChoice = .standard

    var body: some View {
        Image(systemName: "chevron.up")
            // Semibold at 8pt rather than bold at 9: at bold the run of arrows read as a
            // second dotted line competing with the track, which is precisely the thing a
            // direction hint must not do.
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(tint)
            .rotationEffect(.degrees(bearingDeg))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private extension DirectionChevron {
    /// Mixed towards the label colour rather than simply tinted: a teal arrow drawn on the
    /// teal flying track would be invisible, and this stays phase-coloured while separating
    /// from the line in both light and dark mode.
    var tint: Color {
        // Over photography the label colour is the wrong end of the scale: it is dark in light
        // mode, and an arrow that had to lose every contest with the event dots would instead
        // lose to the water. Mixed towards white there, on the same ladder of weights.
        if ground.isImagery {
            switch style {
            case .flying:
                return DesignTokens.Phase.flying.mix(with: .white, by: 0.5).opacity(0.85)
            case .offFoil: return Color.white.opacity(0.6)
            case .neutral: return Color.white.opacity(0.4)
            }
        }
        switch style {
        case .flying:
            return DesignTokens.Phase.flying.mix(with: Color(.label), by: 0.55).opacity(0.62)
        case .offFoil: return Color(.label).opacity(0.38)
        case .neutral: return Color(.label).opacity(0.22)
        }
    }
}

/// The chevron set as it stands for the current camera, and the heading it was built for.
///
/// Kept as a value the two maps each own a copy of: the spacing is in screen points, so the
/// answer depends on the camera and the view size, and both change independently on the
/// full-screen map. Rebuilding is a walk over the track — cheap enough to do on every camera
/// *end*, which is why the frequency is `.onEnd` rather than continuous.
struct DirectionField {
    private(set) var chevrons: [TrackDirection.Chevron] = []
    private(set) var headingDeg: Double = 0
    private var region: MKCoordinateRegion?
    private var size: CGSize = .zero

    mutating func camera(moved context: MapCameraUpdateContext, detail: SessionDetail) {
        region = context.region
        headingDeg = context.camera.heading
        rebuild(detail)
    }

    mutating func resized(to size: CGSize, detail: SessionDetail) {
        guard size != self.size else { return }
        self.size = size
        // Before the camera has settled once there is no region to decimate against, and a
        // layout pass is the earliest moment the chevrons can be built at all.
        if region == nil { region = detail.initialRegion }
        rebuild(detail)
    }

    private mutating func rebuild(_ detail: SessionDetail) {
        guard let region, size.width > 0, size.height > 0 else {
            chevrons = []
            return
        }
        let span = region.span
        let scale = TrackDirection.metresPerPoint(latSpan: span.latitudeDelta,
                                                  lonSpan: span.longitudeDelta,
                                                  centerLat: region.center.latitude,
                                                  widthPoints: size.width,
                                                  heightPoints: size.height)
        let box = TrackDirection.Box(centerLat: region.center.latitude,
                                     centerLon: region.center.longitude,
                                     latSpan: span.latitudeDelta,
                                     lonSpan: span.longitudeDelta)
        chevrons = TrackDirection.chevrons(along: detail.directionPoints,
                                           metresPerPoint: scale, within: box)
    }
}

/// The replay marker: deliberately unlike the outcome dots (bigger, white-ringed, with a
/// halo) so it reads as "where you are now" rather than "something happened here".
private struct PlayheadDot: View {
    let flying: Bool

    var body: some View {
        let tint = flying ? DesignTokens.Phase.flying : DesignTokens.Phase.offFoil
        ZStack {
            Circle().fill(tint.opacity(0.28)).frame(width: 28, height: 28)
            Circle()
                .fill(tint)
                .stroke(.white, lineWidth: 2.5)
                .frame(width: 15, height: 15)
        }
        .shadow(radius: 2)
    }
}

extension SessionDetail {
    var region: MKCoordinateRegion {
        guard let bounds else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 45.87,
                                                                     longitude: 10.87),
                                      span: MKCoordinateSpan(latitudeDelta: 0.05,
                                                             longitudeDelta: 0.05))
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: bounds.centerLat, longitude: bounds.centerLon),
            span: MKCoordinateSpan(latitudeDelta: bounds.latSpan, longitudeDelta: bounds.lonSpan))
    }

    /// The camera both maps open on. Identical to `region` in a shipping build; the debug
    /// hook exists because the chevron spacing is a function of the zoom, and `simctl` has
    /// no fingers to pinch a second scale into existence.
    var initialRegion: MKCoordinateRegion {
        #if DEBUG && targetEnvironment(simulator)
        // `UI_MAP_ZOOM=<factor>` tightens the camera by that factor around the same centre.
        if let factor = ProcessInfo.processInfo.environment["UI_MAP_ZOOM"]
            .flatMap(Double.init), factor > 1 {
            let region = self.region
            return MKCoordinateRegion(
                center: region.center,
                span: MKCoordinateSpan(latitudeDelta: region.span.latitudeDelta / factor,
                                       longitudeDelta: region.span.longitudeDelta / factor))
        }
        #endif
        return region
    }

    /// The track as one polyline with the phase carried per point — the input the chevron
    /// decimation walks. Flattened rather than fed segment by segment: spacing has to be
    /// continuous across a takeoff, or every short off-foil run would collect its own
    /// cluster of arrows.
    var directionPoints: [TrackDirection.Point] {
        segments.flatMap { segment in
            segment.points.map {
                TrackDirection.Point(lat: $0.lat, lon: $0.lon, flying: segment.flying)
            }
        }
    }
}
