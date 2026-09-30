import SwiftUI
import WingFoilKit

#if BETA
/// **The Beta chip** — one small word on every feature the App Store build has not got
/// (Jan, 30 September 2026). A tap opens the Beta page, which lists the feature and asks
/// how it works.
///
/// One component for every surface: the session story, the share composer's video and
/// *Send to us*, the library's grouping and its Apple Watch way in, Settings → Apple Health
/// and the Import screen's Apple Health door. **Beta and dev only**: the whole type is
/// `#if BETA`, so the release binary carries no chip and no call to one.
///
/// Tinted rather than grey, because it is a control (docs/review-checklist.md, pattern G),
/// and set in the accent at caption weight so it reads at a glance without competing with
/// the label beside it.
struct BetaChip: View {
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Text(BetaGuide.chip)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                .fixedSize()
                .contentShape(.capsule)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(BetaGuide.chip)
        .accessibilityHint(BetaGuide.chipHint)
        .sheet(isPresented: $showing) { BetaView() }
    }
}
#endif
