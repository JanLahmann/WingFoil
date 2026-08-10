import SwiftUI
import WingFoilKit

struct SessionRowView: View {
    let row: SessionRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(SessionDisplay.title(row))
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(SessionDisplay.badge(row))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(SessionDisplay.badgeColor(row).opacity(0.16), in: .capsule)
                    .foregroundStyle(SessionDisplay.badgeColor(row))
            }

            Text("\(Fmt.date(row.startDate)) · \(Fmt.duration(row.durationS))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                metric("figure.wave", Fmt.pct(row.foilPct), "foil")
                metric("arrow.triangle.turn.up.right.diamond",
                       "\(row.flightCount ?? 0)", "flights")
                metric("speedometer", Fmt.kn(row.best2sKn), "best 2s")
                metric("point.topleft.down.curvedto.point.bottomright.up", Fmt.km(row.distanceKm),
                       "distance")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func metric(_ symbol: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).imageScale(.small)
            Text(value).monospacedDigit().foregroundStyle(.primary)
        }
        .accessibilityLabel("\(label) \(value)")
    }
}
