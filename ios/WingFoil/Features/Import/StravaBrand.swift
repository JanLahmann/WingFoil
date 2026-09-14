import SwiftUI
import WingFoilKit

/// Strava's brand, used the way Strava's brand guidelines require it to be used
/// (developers.strava.com/guidelines, read 14 September 2026).
///
/// **Why this is not a style choice.** Every API application that shows a Strava connection
/// agrees to three rules, and an app that breaks them can have its application revoked — which
/// for CleanJibe would take out a whole import door and every session already behind it. The
/// three:
///
/// 1. **The connect action is Strava's own button**, unaltered, not a label of our own
///    spelling. The wording is "Connect with Strava", not "Connect Strava", and the artwork is
///    theirs: the assets below are the orange PNGs out of `1.1-Connect-with-Strava-Buttons.zip`
///    at 1× and 2×, uncropped and unrecoloured, in the asset catalogue under `Strava/`.
/// 2. **Attribution wherever Strava data is shown.** The "Compatible with Strava" logo
///    (`1.2-Strava-API-Logos.zip`) marks the Import screen's Strava section. It is placed
///    *beside* CleanJibe's own section, never above the CleanJibe mark — the guideline is that
///    Strava's logo may not be given more prominence than the app's own.
/// 3. **A link back to the activity on Strava** from anything that shows data taken from it —
///    the "View on Strava" link on a session's Log tab.
///
/// **Why the image and not a drawn button.** A button we draw is a button that drifts: a
/// corner radius, a shade of orange, a font the next iOS changes. The supplied PNG is the
/// thing Strava reviews against. `styled` below exists only as the honest fallback for a build
/// whose asset catalogue somehow lost the artwork, and it follows the same spec — #FC5200,
/// white text, 48 pt tall — rather than inventing a look.
enum StravaBrand {

    /// Strava orange, as the brand book states it: #FC5200. Used for the "View on Strava"
    /// link and for the fallback button, and for nothing else — it is not one of the app's
    /// own tokens and must not become one.
    static let orange = Color(red: 0xFC / 255, green: 0x52 / 255, blue: 0x00 / 255)

    /// The supplied button's artwork is 237 × 48 at 1×, so 48 pt is its natural height and
    /// the width follows from the aspect. Strava's guidelines allow the button to be scaled
    /// but not reproportioned, so nothing here sets a width.
    static let buttonHeight: CGFloat = 48

    /// The asset names, in one place so a rename cannot half-happen.
    static let buttonAsset = "StravaConnectButton"
    static let compatibleAsset = "StravaCompatible"

    /// Where an imported session lives on Strava. The id is the one the import wrote into
    /// the recording's filename (`StravaImport.filename`), read back by
    /// `StravaImport.activityId(originalFilename:)`.
    static func activityURL(id: String) -> URL? {
        URL(string: "https://www.strava.com/activities/\(id)")
    }

    /// Whether the artwork is actually in this build. Asked rather than assumed, because the
    /// fallback below is only correct if it is only ever used.
    static var hasArtwork: Bool { UIImage(named: buttonAsset) != nil }
}

/// **"Connect with Strava"** — Strava's own button, and the only control that starts a
/// connection.
///
/// It is a `Button` with the artwork as its whole label, which is what makes the image the
/// control rather than a decoration next to one: the tap target is the button, 48 pt tall,
/// well over the 44 pt minimum. `.buttonStyle(.plain)` keeps a `List` from tinting the
/// artwork, which would be exactly the alteration the guidelines forbid.
struct StravaConnectButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            if StravaBrand.hasArtwork {
                Image(StravaBrand.buttonAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(height: StravaBrand.buttonHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Connect with Strava")
            } else {
                styled
            }
        }
        .buttonStyle(.plain)
        .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    /// The fallback for a build with no artwork: the same words, the same height, the brand's
    /// own orange. Never the preferred path — see `StravaBrand`.
    private var styled: some View {
        Text("Connect with Strava")
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: StravaBrand.buttonHeight)
            .background(StravaBrand.orange, in: .capsule)
    }
}

/// The **"Compatible with Strava"** attribution mark.
///
/// Small, quiet, and deliberately *beside* the section it attributes rather than over it: the
/// guidelines say Strava's logo may not be given more prominence than the app's own, and the
/// CleanJibe mark is the one this screen belongs to. Absent rather than substituted when the
/// artwork is missing — a text stand-in reading "Compatible with Strava" would be a
/// wordmark of our own making, which is the one thing a brand guideline exists to prevent.
struct StravaCompatibleMark: View {
    /// 14 pt tall: legible, and a third of the connect button, which is the proportion that
    /// keeps it an attribution rather than a second offer.
    var height: CGFloat = 14

    var body: some View {
        if UIImage(named: StravaBrand.compatibleAsset) != nil {
            Image(StravaBrand.compatibleAsset)
                .resizable()
                .scaledToFit()
                .frame(height: height)
                .accessibilityLabel("Compatible with Strava")
        }
    }
}

/// **"View on Strava"** — rule 3: anything showing data taken from Strava links back to it.
///
/// Bold and in Strava's orange, which is what the guidelines ask of a text link where the
/// button artwork would be too heavy; on a session's Log tab it sits under the recording's
/// own facts, where the question "where did this come from" is already being answered.
struct StravaActivityLink: View {
    let activityID: String

    var body: some View {
        if let url = StravaBrand.activityURL(id: activityID) {
            Link(destination: url) {
                Label("View on Strava", systemImage: "arrow.up.right.square")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(StravaBrand.orange)
            }
        }
    }
}
