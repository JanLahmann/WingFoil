import MapKit
import SwiftUI
import WingFoilKit

/// The ground under the track: what a `MapStyleChoice` becomes in MapKit, how the track
/// survives being drawn on a photograph, and the control that switches between the four.
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
            recipe.excludesPointsOfInterest == true ? .excludingAll : .all
        switch recipe.base {
        case .standard:
            return .standard(elevation: .flat,
                             emphasis: recipe.isMuted ? .muted : .automatic,
                             pointsOfInterest: poi)
        case .imagery:
            return .imagery(elevation: .flat)
        case .hybrid:
            return .hybrid(elevation: .flat, pointsOfInterest: poi)
        }
    }
}

/// How the track stays readable over photography.
///
/// Over the vector styles nothing changes: foil-teal on a pale grey map is the contrast the
/// whole colour vocabulary was chosen against, and adding an outline there would thicken every
/// line for no reason. Over imagery the same teal lands on sunlit chop, dark water, wet sand
/// and white wake within one session, and splash-cyan lands on the exact colour of the thing
/// it is marking. So on those two styles every stroke and every mark gets a dark outer edge —
/// not a recolour: the phase inks are the contract (docs/presentation.md, "Colour and glyph
/// vocabulary") and may not shift because of what is underneath them. A halo is the one way to
/// raise contrast without touching the ink.
///
/// It is deliberately **soft**. A hard black keyline would read as a second, wider track and
/// turn a busy corner into a dark smear; 55 % black spread three points either side is enough
/// separation for the eye and disappears as soon as you stop looking for it.
enum TrackHalo {

    /// The outer edge's ink. Black rather than the system background, because this only ever
    /// appears over photography — where "the background" is whatever the sea happened to be
    /// doing — and it must not invert with the rider's light/dark setting.
    static let ink = Color.black.opacity(0.55)

    /// How much wider the halo stroke is than the line it backs, in points, total. Three
    /// either side of a 4 pt flying track is a 10 pt stroke, which is still a line.
    static let spread: CGFloat = 6

    static func width(under lineWidth: CGFloat) -> CGFloat { lineWidth + spread }

    /// The other half of surviving a photograph, and the half a halo cannot do on its own.
    ///
    /// Everything in the track vocabulary that is **not a hue** is drawn in an ink —
    /// `Color.secondary` for the off-foil track, `Color.primary` for the direction chevrons,
    /// `Color.secondary` again for the Turns map's deliberately quiet route. Those are
    /// *semantic label colours*: they assume the app's own background is behind them, so in
    /// light mode they are dark grey, which is right on a pale vector map and invisible on a
    /// photograph of deep water. A dark halo under a dark grey line makes it worse, not
    /// better: the two merge into one black worm.
    ///
    /// So over imagery the inks resolve to the light end instead — the same intent ("quieter
    /// than the teal"), read against what is actually underneath. **The hues never move**:
    /// foil-teal, the outcome ladder, splash-cyan and the effort orange are the contract
    /// (docs/presentation.md, "Colour and glyph vocabulary") and mean the same thing on every
    /// ground. These were never colours; they were contrast.
    ///
    /// The two opacities are separate arguments because they are not the same number: white on
    /// photography needs more presence than grey on paper to read as the same weight.
    static func ink(_ base: Color, on style: MapStyleChoice,
                    opacity: Double, overImagery: Double) -> Color {
        style.isImagery ? Color.white.opacity(overImagery) : base.opacity(opacity)
    }

    /// The same idea for an annotation, which is a view rather than a stroke: a shadow with no
    /// offset is an outline that follows whatever shape the marker happens to be, so the
    /// takeoff arrow, the splash drop and the outcome dots all get one without any of them
    /// having to know it exists.
    @ViewBuilder
    static func around(_ marker: some View, on style: MapStyleChoice) -> some View {
        if style.isImagery {
            marker.shadow(color: ink, radius: 2.5)
                  .shadow(color: ink.opacity(0.6), radius: 1)
        } else {
            marker
        }
    }
}

/// The map-style control: one chip among the legend chips.
///
/// It sits in the legend row rather than in Settings because that is where the rider is when
/// he wants it — looking at the map, having just failed to recognise the bay — and because the
/// legend row is already the map's control strip. It is a `Menu` rather than a fifth kind of
/// chip: four mutually exclusive options are a *choice*, not four toggles, and four more
/// capsules would double the width of a row that already wraps on a narrow phone.
///
/// The closed control wears the current style's glyph and name, so the strip says what the map
/// is on without anybody opening anything.
struct MapStyleChip: View {

    @Environment(SessionStore.self) private var store

    var body: some View {
        Menu {
            Picker("Map style", selection: Binding(get: { store.mapStyle },
                                                   set: { store.mapStyle = $0 })) {
                ForEach(MapStyleChoice.allCases) { choice in
                    Label(choice.label, systemImage: choice.symbolName).tag(choice)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: store.mapStyle.symbolName)
                    .font(.system(size: 10))
                Text(store.mapStyle.label.lowercased())
                    .lineLimit(1)
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
