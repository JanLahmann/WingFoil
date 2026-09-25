import MapKit
import SwiftUI
import WingFoilKit

/// The ground under the track: what a `MapStyleChoice` becomes in MapKit, how the track
/// survives being drawn on a photograph, and the control that switches between the two.
///
/// The choice itself lives in the kit (`MapStyleChoice`) because it is a rule with a table in
/// it; everything here is the SwiftUI half that cannot be tested on a Mac.

extension MapStyleChoice {

    /// Built from `recipe` rather than from a second `switch` on the case, so the table the
    /// tests assert is the table that ships. `MapStyle` is opaque and not `Equatable` — this
    /// is the only place the two can be kept honest with each other.
    var mapStyle: MapStyle {
        let recipe = self.recipe
        let poi: PointOfInterestCategories =
            recipe.excludesPointsOfInterest ? .excludingAll : .all
        switch recipe.base {
        case .standard:
            return .standard(elevation: .flat, emphasis: .automatic, pointsOfInterest: poi)
        case .hybrid:
            return .hybrid(elevation: .flat, pointsOfInterest: poi)
        }
    }
}

/// How the track stays readable over photography.
///
/// Over the vector map nothing changes: foil-teal on a pale grey map is the contrast the whole
/// colour vocabulary was chosen against, and an outline there would thicken every line for no
/// reason. Over photography the same line lands on deep water, sunlit chop, wet sand and white
/// wake within one session, so every stroke and every mark is drawn from
/// `TrackPalette.imagery` (the kit, where its contrast on each ground is a test): a **crisp
/// dark casing** under every line and around every mark, and inks lifted to the light end.
///
/// The casing is narrow and dense on purpose. The first version was a wide, soft 55 % black
/// band three points either side, and on a bright photograph it read as a dirty smear along
/// the line rather than as an edge (Jan, F8i: "breadcrumb colors for satellite map is not
/// nice"). A 1.5 pt edge at 70 % is the keyline every map over imagery uses.
enum TrackHalo {

    private static var palette: TrackPalette { .imagery }

    /// The casing's ink. Black rather than the system background, because this only ever
    /// appears over photography and must not invert with the rider's light/dark setting.
    static let ink = color(TrackPalette.imagery.casing!)

    /// How much wider the casing stroke is than the line it backs, in points, total.
    static let spread = CGFloat(TrackPalette.imagery.casingEdge * 2)

    static func width(under lineWidth: CGFloat) -> CGFloat { lineWidth + spread }

    /// A kit ink as a SwiftUI colour, in sRGB so it never adapts to the theme.
    static func color(_ ink: TrackPalette.Ink) -> Color {
        Color(.sRGB, red: ink.r, green: ink.g, blue: ink.b, opacity: ink.a)
    }

    /// The flying line over photography: phase teal lifted towards white, so it keeps its
    /// meaning and gains the brightness deep water takes away.
    static let flyingOverImagery = color(TrackPalette.imagery.flying!)

    /// The other half of surviving a photograph, and the half a casing cannot do on its own.
    ///
    /// Everything in the track vocabulary that is **not a hue** is drawn in an ink —
    /// `Color.secondary` for the off-foil track, `Color.primary` for the direction chevrons,
    /// `Color.secondary` again for the Turns map's deliberately quiet route. Those are
    /// semantic label colours: dark grey in light mode, right on a pale vector map and
    /// invisible on a photograph of deep water. So over imagery they resolve to the light end
    /// instead — the same intent ("quieter than the teal"), read against what is underneath.
    /// The verdict and effort hues never move.
    static func ink(_ base: Color, on style: MapStyleChoice,
                    opacity: Double, overImagery: Double) -> Color {
        style.isImagery ? Color.white.opacity(overImagery) : base.opacity(opacity)
    }

    /// The same casing for an annotation, which is a view rather than a stroke: a shadow with
    /// no offset is an outline that follows whatever shape the marker happens to be. Two tight
    /// passes rather than one wide blur, so it reads as an edge and not as a smudge.
    @ViewBuilder
    static func around(_ marker: some View, on style: MapStyleChoice) -> some View {
        if style.isImagery {
            let radius = CGFloat(palette.markerOutline)
            marker.shadow(color: ink, radius: radius)
                  .shadow(color: ink, radius: radius * 0.5)
        } else {
            marker
        }
    }
}

/// The map-style control: one chip among the legend chips.
///
/// It sits in the legend row rather than in Settings because that is where the rider is when
/// he wants it — looking at the map, having just failed to recognise the bay — and because the
/// legend row is already the map's control strip. It is a `Menu` rather than a toggle chip so
/// it reads as a choice of ground and never as one more layer to switch off.
///
/// The closed control wears the current style's glyph and name, so the strip says what the map
/// is on without anybody opening anything.
struct MapStyleChip: View {

    @Environment(SessionStore.self) private var store

    var body: some View {
        Menu {
            Picker("Map style", selection: Binding(get: { store.mapStyle },
                                                   set: {
                store.mapStyle = $0
                Usage.record(.mapStyle, detail: $0.rawValue)
            })) {
                ForEach(MapStyleChoice.allCases) { choice in
                    Label(choice.label, systemImage: choice.symbolName).tag(choice)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: store.mapStyle.symbolName)
                    .font(.caption2)
                Text(store.mapStyle.label.lowercased())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.14)))
            .foregroundStyle(.secondary)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Map style")
        .accessibilityValue(store.mapStyle.accessibilityNoun)
    }
}
