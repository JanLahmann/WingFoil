import SwiftUI
import WingFoilKit

#if BETA
/// **Next session** — the top of the Turns tab, in beta and dev (rider review I2, 9 Oct
/// 2026): the commonest "Next time…" tip of the afternoon, and port against starboard.
///
/// Layout only. What it says, and when it says nothing, is `NextSessionCoach`'s; the tip's
/// sentence is the turn page's own (`TurnCoach.tipText`), so the card and the ten pages
/// behind it cannot word one tip two ways. Session-wide, like the cards under it: the
/// type/side filters lower down the tab do not move it. Absent when the coach has nothing.
struct NextSessionCard: View {
    let detail: SessionDetail

    var body: some View {
        let coach = NextSessionCoach.make(turns: detail.analysis.turns,
                                          samples: detail.sliceSamples,
                                          windDirDeg: detail.windDirDeg,
                                          quietS: detail.analysis.config.turnCleanQuietS)
        if !coach.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(NextSessionCoach.title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if let tip = coach.tip {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tip.text)
                            .font(.subheadline.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(NextSessionCoach.countLine(tip))
                            .font(.caption2)
                            .foregroundStyle(.readableSecondary)
                    }
                }
                if let sides = coach.sides {
                    if coach.tip != nil { Divider() }
                    VStack(alignment: .leading, spacing: 4) {
                        sideRow(sides.port, sides: sides)
                        sideRow(sides.starboard, sides: sides)
                        if let verdict = NextSessionCoach.sideVerdict(sides) {
                            Text(verdict)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            .id("nextSession")
        }
    }

    /// "Starboard entry · 1 of 3 jibes clean", the weaker side's count in bold.
    private func sideRow(_ count: NextSessionCoach.SideCount,
                         sides: NextSessionCoach.Sides) -> some View {
        let weaker = sides.weaker == count.side
        return HStack(spacing: 6) {
            Text(NextSessionCoach.sideTitle(count))
                .font(.subheadline)
            Spacer(minLength: 8)
            if sides.measure == .cleanJibes {
                Image(systemName: DesignTokens.Glyph.cleanJibe)
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Clean.jibe)
                    .accessibilityHidden(true)
            }
            Text(NextSessionCoach.sideValue(count, measure: sides.measure))
                .font(.subheadline.monospacedDigit().weight(weaker ? .semibold : .regular))
                .foregroundStyle(weaker ? AnyShapeStyle(.primary)
                                        : AnyShapeStyle(.readableSecondary))
        }
    }
}
#endif
