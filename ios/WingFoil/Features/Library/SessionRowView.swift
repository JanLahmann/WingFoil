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
                // the same string the session page opens with (docs/presentation/one-clock.md, "One
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
                // (docs/presentation/not-a-session-spots.md, "Not a session"). Nothing is deleted and nothing is
                // hidden — it is simply out of the totals, and this is where the rider finds
                // out why the row he can see is not in the number he is reading. A
                // provisional row already carries its own blue note above, and one row does
                // not need two ways of saying "not yet".
                if !row.isSession, !row.isProvisional {
                    Text(NotASessionNote.tag)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // **Three numbers, each under its own word** (Jan, Beta 75; pattern H).
                // The row used to read "37 % · 3 · 13.25 kn" under three glyphs, and the
                // middle glyph — a turning arrow — drew the *flight* count, which is not
                // what a turning arrow means to anybody. Which three they are is now the
                // rider's (Settings → Session list → Row shows); what each one is called
                // is the kit's, so the word is the same here, on the session page and in
                // the picker (`RowMetric`).
                HStack(spacing: 12) {
                    ForEach(Array(store.rowMetrics.enumerated()), id: \.offset) { _, choice in
                        metric(choice)
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                // Three figures side by side under the date. They scale, and stop where
                // three of them stop fitting a phone's width — the row above them and the
                // title above that scale the whole way.
                .denseRowTypeSizeCap()

                HStack(spacing: 10) {
                    // With its words. "4 · 1 · 0" is the ladder in three colours and
                    // nothing else, and a colour is not a word (pattern H).
                    OutcomeTally(flewThrough: row.turnsFlewThrough ?? 0,
                                 touchdown: row.turnsTouchdown ?? 0,
                                 fellIn: row.turnsFellIn ?? 0,
                                 words: true)
                    Text(Fmt.km(row.distanceKm))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.readableSecondary)
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
                    // The inset is the backdrop's, not a number typed here: the map behind
                    // the line is a picture of the square this inset leaves, and two insets
                    // that drift apart draw the map at a different scale from the track on
                    // top of it (Jan, Beta 75).
                    TrackOutlineView(thumbnail: thumbnail, padding: ListMapBackdrop.inset)
                } else {
                    Image(systemName: thumbnail == nil ? "map" : "location.slash")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
            }
            // The tile the snapshot is taken of, from the one place that says how big it is.
            .frame(width: ListMapBackdrop.size.width, height: ListMapBackdrop.size.height)
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

    /// One cell: the glyph and the number, with the word directly under it — the shape the
    /// watch draws the same three facts in. The word is what makes the glyph readable; the
    /// glyph is what makes the row scannable once the word has been read once.
    private func metric(_ choice: RowMetric) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: choice.icon).imageScale(.small)
                Text(choice.format(row)).monospacedDigit().foregroundStyle(.primary)
            }
            Text(choice.label)
                .font(.caption2)
                .foregroundStyle(.readableSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(choice.label + " " + choice.format(row))
    }
}
