import SwiftUI
import WingFoilKit

/// **How wide the drawn window is** — the lead-in before the sweep and the run-out after it,
/// remembered per phone.
///
/// The pads were one constant, `TurnSlice.defaultPadS = 8`, and eight seconds is a good
/// default and a bad only-option. Two things it cannot do: it cannot hold the clean jibe's
/// **quiet tail**, which closes ten seconds after the sweep, so the strip's `quiet` rule was
/// drawn "only where it fits" and in practice never fitted; and it cannot show what a fall
/// actually did, where the interesting part is the forty seconds of swimming that the outcome
/// window is measured over and the drawing stopped eight seconds in.
///
/// So the dev build gets two sliders. They are a *reading* preference rather than a fact about
/// a turn — a rider who wants to see the run-out wants to see it on every turn — so they live
/// in `@AppStorage` beside the orientation and the ghost toggle, and they survive the sheet
/// being closed.
///
/// **Not in the public build.** The window is part of what the page means: "the drawing is
/// 8 s either side of the sweep" is a sentence in the footnote and a promise that two turns
/// are drawn at the same scale in time. A control that broke that promise silently, on a
/// screen a rider reads to compare his jibes, would cost more than it gave.
struct TurnWindowPads: Equatable {
    var beforeS: Double
    var afterS: Double

    static let standard = TurnWindowPads(beforeS: TurnSlice.defaultPadS,
                                         afterS: TurnSlice.defaultPadS)
}

#if TUNING
/// The two sliders, and the one sentence that says what they cost.
struct TurnWindowControl: View {
    @Binding var beforeS: Double
    @Binding var afterS: Double
    /// The quiet tail from this analysis' own config echo, so the note can say whether the
    /// run-out is now wide enough to draw its rule — which is the main reason to touch these.
    var quietS: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            slider("Lead-in", value: $beforeS, range: TurnSlice.padBeforeRangeS)
            slider("Run-out", value: $afterS, range: TurnSlice.padAfterRangeS)
            if let quietS, quietS > 0 {
                Text(afterS >= quietS
                     ? "The run-out now reaches the quiet tail, so the \"quiet\" rule is drawn."
                     : "The quiet tail closes \(Int(quietS)) s after the sweep — widen the "
                       + "run-out past that to see its rule.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func slider(_ label: String, value: Binding<Double>,
                        range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            // Whole seconds: the window is a framing choice, and a tenth of a second of
            // lead-in is not a choice anybody is making.
            Slider(value: value, in: range, step: 1)
            Text("\(Int(value.wrappedValue)) s")
                .font(.caption.monospacedDigit())
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) seconds")
    }
}
#endif
