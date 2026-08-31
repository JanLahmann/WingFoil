import SwiftUI
import WingFoilKit

/// One library row: the track at a glance on the left, the numbers on the right.
///
/// The thumbnail and the sparkline come from `ThumbnailStore`, which builds them lazily
/// and caches them to disk — so the row draws a placeholder for a fraction of a second on
/// a session's first ever appearance and never again.
struct SessionRowView: View {
    let row: SessionRow
    @Environment(ThumbnailStore.self) private var thumbnails

    private var thumbnail: TrackThumbnail? { thumbnails.thumbnail(for: row.id) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            preview
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(SessionDisplay.title(row))
                        .font(.headline)
                        .lineLimit(1)
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
                            .frame(maxWidth: 130, alignment: .trailing)
                    }
                    if row.isProvisional { ProvisionalBadge() }
                    Text(SessionDisplay.badge(row))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(SessionDisplay.badgeColor(row).opacity(0.16), in: .capsule)
                        .foregroundStyle(SessionDisplay.badgeColor(row))
                }

                Text("\(Fmt.date(row.startDate, zone: row.displayZone)) · \(Fmt.duration(row.durationS))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let note = SessionDisplay.provisionalNote(row) {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(Color.blue)
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

                HStack(spacing: 10) {
                    OutcomeTally(flewThrough: row.turnsFlewThrough ?? 0,
                                 touchdown: row.turnsTouchdown ?? 0,
                                 fellIn: row.turnsFellIn ?? 0)
                    Text(Fmt.km(row.distanceKm))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 4)
        .task { thumbnails.request(row) }
    }

    /// Track outline over a speed sparkline. Both degrade on their own: a recording with
    /// no positions still shows its speed shape, and one with no speed channel still shows
    /// where it went.
    private var preview: some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemFill))
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

            if let thumbnail, thumbnail.speed.count >= 2 {
                SpeedSparklineView(values: thumbnail.speed)
                    .frame(width: 62, height: 14)
            } else {
                Color.clear.frame(width: 62, height: 14)
            }
        }
        .accessibilityHidden(true)
    }

    private func metric(_ symbol: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).imageScale(.small)
            Text(value).monospacedDigit().foregroundStyle(.primary)
        }
        .accessibilityLabel("\(label) \(value)")
    }
}
