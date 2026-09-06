import CoreLocation
import MapKit
import SwiftUI
import WingFoilKit

/// **Every attempt to get up, on the water it happened on** — the Takeoffs tab's drill-in,
/// and the mirror of `TurnsAnalysisView` one tab to the left.
///
/// The takeoff tiles above it say how many attempts there were and how many failed. They
/// could not say *where*, and where is most of the answer: a rider whose failures cluster at
/// one end of the bay was fighting a lee shore or a wind shadow, not his own technique, and
/// nothing on the page had ever told him so. The failed-attempt count spent its life as a
/// clause in the map legend's body copy, then became this tab's headline; this is the next
/// step of the same move — the number, and then the picture of it.
///
/// **Two controls, two questions.** The outcome chips are a *data* filter: they choose which
/// attempts the page is about, and the pins, the spans, the caption and the list move
/// together. The legend under the map is a *layer* filter over this map's own stored set
/// (`MapLayerScope.takeoffs`): it chooses what is drawn about them — the glyphs, the pumping
/// spans, the splashes, the chevrons. Filtering to failures and hiding the pumping runs are
/// different intentions, so they are different controls, and neither is allowed to imply the
/// other.
struct TakeoffsAnalysisView: View {
    let detail: SessionDetail

    /// Read here for what this page shares with every other map: the ground it is drawn on
    /// and this map's own layer set.
    @Environment(SessionStore.self) private var store

    @State private var filter = TakeoffOutcomeFilter.all
    /// The attempt the reader pointed at, drawn larger on the map and banded in the list.
    /// Transient, like the record-window picker — it is a way of pointing, not a preference.
    @State private var focused: Int?

    private var visibility: MapLayerVisibility { store.mapLayers(for: .takeoffs) }

    /// The attempts that survived the outcome chips, in time order (`takeoffMarks` already
    /// is).
    private var attempts: [SessionDetail.TakeoffMark] {
        detail.takeoffMarks.filter { filter.accepts($0.attemptKind) }
    }

    /// The pumping runs that belong to the attempts on screen. A free takeoff is a takeoff
    /// with no burst, so filtering to free leaves no spans at all — which is the honest
    /// drawing of "he did not pump for these".
    private var spans: [SessionDetail.PumpSpan] {
        detail.pumpSpans.filter { span in
            switch filter {
            case .all: return true
            case .success: return span.outcome == .success
            case .failed: return span.outcome == .failed
            case .free: return false
            }
        }
        .filter { $0.points.count >= 2 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("All \(detail.takeoffMarks.count) attempts")
                .font(.headline)
            chips
            if !detail.segments.isEmpty { map }
            list
            footnote
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #if DEBUG && targetEnvironment(simulator)
        // Screenshot hook, the same family as `UI_TURN_FILTER`: `simctl` cannot tap a chip,
        // so `UI_TAKEOFF_FILTER=failed` opens the tab with the filter already engaged.
        .onAppear {
            guard let raw = ProcessInfo.processInfo.environment["UI_TAKEOFF_FILTER"],
                  let value = TakeoffOutcomeFilter(rawValue: raw) else { return }
            filter = value
        }
        #endif
    }

    // MARK: - The data filter

    /// One segmented control rather than the Turns tab's two, because there is one question
    /// here: did it get up. `Free` is deliberately last and deliberately inside `Success` —
    /// it narrows the successes to the ones the wind did, exactly as "clean" narrows the
    /// jibes that flew through.
    private var chips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Outcome", selection: $filter) {
                ForEach(TakeoffOutcomeFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Attempt outcome")
            Text("A free takeoff got up on the wind alone — it is one of the successes, "
                 + "not a third outcome beside them.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .id("takeoffFilters")
    }

    // MARK: - Map

    /// The session's track receding, this page's attempts on it, and the runs he pumped to
    /// produce them. The frame is `FocusMapView`, shared with the Turns tab.
    private var map: some View {
        FocusMapView(detail: detail, scope: .takeoffs, caption: caption) {
            // Under the glyphs, because a pumping run is the context for the attempt that
            // ends it and not a thing to read on its own — the same order the session map
            // draws them in.
            if visibility.isVisible(.pumping) {
                ForEach(spans) { span in
                    MapPolyline(coordinates: span.points.map(\.coordinate))
                        .stroke(EventMarkerStyle.pumping.opacity(0.75),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round,
                                                   lineJoin: .round))
                }
            }
            if visibility.isVisible(.splash) {
                ForEach(detail.splashMarks) { mark in
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: mark.lat,
                                                                      longitude: mark.lon),
                               anchor: .center) {
                        TrackHalo.around(EventMarkerStyle.splashMark(), on: store.mapStyle)
                            .accessibilityHidden(true)
                    }
                    .annotationTitles(.hidden)
                }
            }
            if visibility.isVisible(.takeoff) {
                ForEach(attempts) { mark in
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: mark.lat,
                                                                      longitude: mark.lon),
                               anchor: .center) {
                        // The pin is the other half of the row: tapping it is the same act
                        // as tapping the row, so the two share one focus.
                        Button { focused = focused == mark.id ? nil : mark.id } label: {
                            TrackHalo.around(
                                EventMarkerStyle.takeoffMark(mark,
                                                             size: focused == mark.id ? 20 : 12),
                                on: store.mapStyle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(mark.title), \(mark.detail)")
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .id("takeoffsMap")
    }

    private var caption: String {
        attempts.isEmpty
            ? "Nothing to mark — widen the filter."
            : "\(attempts.count) \(filter.description) marked · "
                + "tap a pin or a row to point at one."
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if attempts.isEmpty {
            ContentUnavailableView("No \(filter.description)",
                                   systemImage: "arrow.up.circle",
                                   description: Text("This session has none. A source with "
                                                     + "no accelerometer cannot see a failed "
                                                     + "attempt at all."))
                .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            VStack(spacing: 0) {
                headerRow
                Divider()
                ForEach(attempts) { mark in
                    Button { focused = focused == mark.id ? nil : mark.id } label: {
                        AttemptRowView(mark: mark, focused: focused == mark.id)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
            .id("takeoffList")
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text("at").frame(width: 46, alignment: .leading)
            Text("pumps").frame(width: 52, alignment: .trailing)
            Text("to foil").frame(width: 56, alignment: .trailing)
            Text("outcome").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var footnote: some View {
        let k = detail.analysis.summary.takeoff
        return VStack(alignment: .leading, spacing: 3) {
            Text("An attempt is a pumping burst and what came of it. The ones that got up "
                 + "are the engine's takeoffs; the ones that did not are the pumping "
                 + "episodes it judged failed, which is why a recording with no "
                 + "accelerometer shows successes only.")
            if k.runsTruncated > 0 {
                Text("\(k.runsTruncated) run\(k.runsTruncated == 1 ? "" : "s") "
                     + "not in the record — the recording started or stopped inside them, "
                     + "so they carry no time to foil.")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One attempt: when, how many strokes, how long it took to fly, and whether it did.
///
/// A missing number is **absent, never 0** (docs/presentation.md, "Formatter rules"): a
/// source with no accelerometer counted no strokes, and a failed attempt never reached the
/// foil — printing zeroes there would turn two absences into two claims.
private struct AttemptRowView: View {
    let mark: SessionDetail.TakeoffMark
    let focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(Fmt.clock(mark.t))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
            Text(mark.pumps.map(String.init) ?? "—")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(mark.pumps == nil ? .tertiary : .secondary)
                .frame(width: 52, alignment: .trailing)
            Text(mark.timeToFoilS.map { String(format: "%.0f s", $0) } ?? "—")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(mark.timeToFoilS == nil ? .tertiary : .secondary)
                .frame(width: 56, alignment: .trailing)
            HStack(spacing: 5) {
                EventMarkerStyle.takeoffMark(mark, size: 11)
                Text(mark.attemptKind.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(focused ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Fmt.clock(mark.t)), \(mark.title), \(mark.detail)")
    }
}
