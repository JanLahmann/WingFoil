import SwiftUI
import WidgetKit

/// The watch-face complication: the CleanJibe mark, and one tap that is already recording.
///
/// **What it is for.** A wingfoiler is standing in knee-deep water with a wing overhead and
/// wet hands. The distance between "watch face" and "recording" was previously: raise wrist,
/// press the crown, find the app in a grid of forty, wait for it to launch, press START.
/// This is one tap on the face. That is the entire feature, and it is why the complication
/// carries `widgetURL` rather than merely launching the app — see `WatchURL`.
///
/// **What it deliberately does not claim.** ADR-016 says the watch detects nothing, so there
/// is no jibe count and no foil percentage here: those numbers exist only after the phone has
/// analysed the recording, and a face that printed a guess at them would be the second answer
/// ADR-016 was written to prevent. The rectangular family shows the three facts the watch
/// itself measured, and "Start session" when there are none — which is every build until the
/// app group exists (`WatchLastSessionStore`).
@main
struct WingFoilWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        StartSessionComplication()
    }
}

// MARK: - Timeline

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let lastSession: WatchLastSession?
}

/// One entry, refreshed hourly.
///
/// There is nothing here that changes on its own: the snapshot only moves when a session is
/// saved, and the app reloads the timeline itself at that moment. The hourly policy is a floor
/// so a relative date does not go stale on a watch whose app is never opened.
struct ComplicationProvider: TimelineProvider {

    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), lastSession: nil)
    }

    func getSnapshot(in context: Context,
                     completion: @escaping (ComplicationEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        completion(Timeline(entries: [entry()],
                            policy: .after(Date().addingTimeInterval(3600))))
    }

    private func entry() -> ComplicationEntry {
        ComplicationEntry(date: Date(), lastSession: WatchLastSessionStore.read())
    }
}

// MARK: - Widget

struct StartSessionComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "de.lahmann.wingfoil.watch.complication.start",
                            provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
                .widgetURL(WatchURL.start)
                // Required on watchOS 10+; the accessory families paint their own ground
                // (`AccessoryWidgetBackground`) where they want one, and a container colour
                // underneath would fight the face's tint.
                .containerBackground(Color.clear, for: .widget)
        }
        .configurationDisplayName("Start session")
        .description("One tap from the watch face to a recording wingfoil session.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular])
    }
}

// MARK: - Views

struct ComplicationView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                mark.padding(7)
            }
        case .accessoryCorner:
            // The corner families are an image plus curved text along the bezel; the label is
            // what tells the rider which app the mark belongs to at 9 pt on a curve.
            mark
                .padding(3)
                .widgetLabel(headline)
        default:
            HStack(spacing: 8) {
                mark.frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("CleanJibe")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text(headline)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
        }
    }

    /// The brand mark as a template: complications are tinted by the watch face, and a
    /// full-colour icon would come back a grey square in every accented and vibrant rendering
    /// mode. `ComplicationMark` is the app icon's artwork with the navy ground taken out.
    private var mark: some View {
        Image("ComplicationMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
    }

    /// "Start session" until there is something true to say, then the last session's own
    /// numbers. Never a jibe count — the watch does not have one (ADR-016).
    private var headline: String {
        guard let session = entry.lastSession else { return "Start session" }
        return ComplicationFormat.day(session.startedAt)
            + " · " + ComplicationFormat.duration(session.durationS)
            + " · " + ComplicationFormat.distance(session.distanceM)
    }
}

/// Two of `WatchFormat`'s rules, restated.
///
/// Not shared with the app's `WatchFormat`: that file sits inside the `WingFoilWatch` target's
/// own source tree, and XcodeGen files such a reference in two groups at different depths and
/// resolves the second to a path that does not exist — the same mechanical trap
/// `Views/WatchBrand.swift` documents for the palette. Two format helpers are cheaper than a
/// broken build, and the rules they copy are one line each.
enum ComplicationFormat {

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// `1:04` past an hour, `42 min` below it — shorter than the app's `m:ss`, because a
    /// complication is read at a glance and the seconds of a finished session are noise.
    static func duration(_ seconds: Double) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// Matches `WatchFormat.distance`: metres under a kilometre, one decimal above.
    static func distance(_ metres: Double) -> String {
        metres < 1000 ? "\(Int(metres)) m" : String(format: "%.1f km", metres / 1000)
    }
}
