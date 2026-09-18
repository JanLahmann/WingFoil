import SwiftUI
import UIKit
import WingFoilKit

/// One library row: the track at a glance on the left, the numbers on the right.
///
/// The thumbnail and the sparkline come from `ThumbnailStore`, which builds them lazily
/// and caches them to disk — so the row draws a placeholder for a fraction of a second on
/// a session's first ever appearance and never again.
struct SessionRowView: View {
    let row: SessionRow
    @Environment(ThumbnailStore.self) private var thumbnails
    @Environment(SessionStore.self) private var store

    private var thumbnail: TrackThumbnail? { thumbnails.thumbnail(for: row.id) }

    /// The map under the outline, when the rider has asked for one (Settings → Session
    /// list) and MapKit has answered. Nil is the ordinary case and draws what the row has
    /// always drawn.
    private var backdrop: UIImage? {
        guard store.listMapBackdrop else { return nil }
        return thumbnails.backdrop(for: row.id, style: store.mapStyle)
    }

    @Environment(\.displayScale) private var displayScale

    /// How much of the row a rider's name may take before the title starts giving way.
    /// Scaled, because at a larger text size 130 pt stops being a name and starts being
    /// three letters and an ellipsis.
    @ScaledMetric(relativeTo: .headline) private var riderBadgeWidth: CGFloat = 130

    /// The discipline capsule, and whether it says anything this reader needs
    /// (`DisciplineReview.showsBadge`): with the windsurf switch off, a library of one rig
    /// spelling "Wingfoil" on every row is a column of noise, while the rows that disagree —
    /// a session read as windsurf, a recording that names its own rig — keep it.
    private var showsBadge: Bool {
        DisciplineReview.showsBadge(SessionDisplay.badge(row),
                                    windsurfEnabled: store.windsurfEnabled)
    }

    /// The `?`: "nobody has said this is what it is". Never drawn while the switch is off —
    /// it is the visible half of a question the app is no longer asking.
    private var isGuess: Bool {
        DisciplineReview.showsGuessMark(guessed: SessionDisplay.badgeIsGuess(row),
                                        windsurfEnabled: store.windsurfEnabled)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            preview
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(SessionDisplay.title(row))
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    if let example = SessionDisplay.exampleBadge(row) {
                        ExampleBadge(text: example, font: .caption2)
                    }
                    if let rider = row.rider {
                        // Priority over the title: "whose session is this" is the one
                        // thing on the row that cannot be inferred from anything else, and
                        // a badge truncated to "Ma…" answers nothing. Capped so a long
                        // name still leaves the title readable.
                        RiderBadge(name: rider)
                            .layoutPriority(1)
                            .frame(maxWidth: riderBadgeWidth, alignment: .trailing)
                    }
                    if row.isProvisional { ProvisionalBadge() }
                    if let chip = row.analysisDiscipline.lexicon.chip {
                    Text(chip)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.16), in: .capsule)
                        .foregroundStyle(.orange)
                }
                // The `?` says nobody has confirmed the discipline yet — a wrong guess is
                // visible at a glance in the list rather than only on the session page.
                if showsBadge {
                    Text(SessionDisplay.badge(row) + (isGuess ? " ?" : ""))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(SessionDisplay.badgeColor(row).opacity(0.16), in: .capsule)
                        .foregroundStyle(SessionDisplay.badgeColor(row))
                        .accessibilityLabel(
                            isGuess
                            ? "Analysed as " + SessionDisplay.badge(row) + ", not confirmed"
                            : SessionDisplay.badge(row))
                }
                }

                // The engine's cleaned span in the block's own spelling — the same number and
                // the same string the session page opens with (docs/presentation.md, "One
                // clock"). It was `Fmt.duration(row.durationS)`: a different clock in a
                // different format, one tap away from the page that disagreed with it.
                Text(Fmt.date(row.startDate, zone: row.displayZone) + " · "
                     + KeyMetrics.duration(row.rateSeconds))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let note = SessionDisplay.provisionalNote(row) {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(Color.blue)
                }

                // A recording that is not a session says so, quietly, and stays in the list
                // (docs/presentation.md, "Not a session"). Nothing is deleted and nothing is
                // hidden — it is simply out of the totals, and this is where the rider finds
                // out why the row he can see is not in the number he is reading. A
                // provisional row already carries its own blue note above, and one row does
                // not need two ways of saying "not yet".
                if !row.isSession, !row.isProvisional {
                    Text(NotASessionNote.tag)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    metric("figure.wave", Fmt.pct(row.foilPct), "foil")
                    metric("arrow.triangle.turn.up.right.diamond",
                           "\(row.flightCount ?? 0)", "flights")
                    metric("speedometer", Fmt.kn(row.best2sKn), "best 2s")
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                // Three figures side by side under the date. They scale, and stop where
                // three of them stop fitting a phone's width — the row above them and the
                // title above that scale the whole way.
                .denseRowTypeSizeCap()

                HStack(spacing: 10) {
                    OutcomeTally(flewThrough: row.turnsFlewThrough ?? 0,
                                 touchdown: row.turnsTouchdown ?? 0,
                                 fellIn: row.turnsFellIn ?? 0)
                    Text(Fmt.km(row.distanceKm))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                // The outcome tally is four numbers in a line; same ceiling, same reason.
                .denseRowTypeSizeCap()
            }
        }
        .padding(.vertical, 4)
        .task { thumbnails.request(row) }
        // After the outline, never instead of it: the snapshot is drawn to the box the
        // outline was fitted into, so there is nothing to line it up with until the
        // outline exists. Asked again when the thumbnail lands and when the style changes.
        .task(id: backdropKey) {
            guard store.listMapBackdrop else { return }
            thumbnails.requestBackdrop(row, style: store.mapStyle, scale: displayScale)
        }
    }

    /// Track outline over a speed sparkline. Both degrade on their own: a recording with
    /// no positions still shows its speed shape, and one with no speed channel still shows
    /// where it went.
    private var preview: some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemFill))
                if let backdrop {
                    Image(uiImage: backdrop)
                        .resizable()
                        .scaledToFill()
                    // The line is the thing being read. Photography at 62 points is texture
                    // rather than information, and a teal stroke over sunlit chop is not
                    // legible without something taken off the ground first.
                    Color.black.opacity(store.mapStyle.isImagery ? 0.22 : 0.10)
                }
                if let thumbnail, !thumbnail.points.isEmpty {
                    TrackOutlineView(thumbnail: thumbnail)
                        .padding(3)
                } else {
                    Image(systemName: thumbnail == nil ? "map" : "location.slash")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(width: 62, height: 44)
            .clipShape(.rect(cornerRadius: 8))

            if let thumbnail, thumbnail.speed.count >= 2 {
                SpeedSparklineView(values: thumbnail.speed)
                    .frame(width: 62, height: 14)
            } else {
                Color.clear.frame(width: 62, height: 14)
            }
        }
        .accessibilityHidden(true)
    }

    /// What a new snapshot is owed to: a session, a style, and the outline it lines up
    /// with. The switch is in it so turning the setting on asks straight away.
    private var backdropKey: String {
        row.id + "-" + store.mapStyle.rawValue
            + (store.listMapBackdrop ? "-on" : "-off")
            + (thumbnail == nil ? "-pending" : "-ready")
    }

    private func metric(_ symbol: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).imageScale(.small)
            Text(value).monospacedDigit().foregroundStyle(.primary)
        }
        .accessibilityLabel("\(label) \(value)")
    }
}
