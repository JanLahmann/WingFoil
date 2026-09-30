import SwiftUI
import UIKit

/// **A segment row takes taps, never a vertical drag** (Jan, 30 Sep 2026, dev 120: "Scroll back
/// up on turns section still does not work … up struggles at exactly this position").
///
/// The look of a segmented `Picker` — a capsule track, one lighter thumb under the selected
/// word — built from plain SwiftUI buttons. It exists because the native control is a
/// `UISegmentedControl`, a `UIControl`, and a scroll view never takes back a touch it has
/// handed to one: a thumb that rests on the row for longer than the scroll view's content
/// delay (≈ 150 ms) before it moves is the control's for good (`touchesShouldCancel(in:)` is
/// false for every `UIControl`), so the page under it did not move. A SwiftUI button lets go
/// of the touch the moment the scroll view starts to pan, so one finger that starts here and
/// goes up or down scrolls the page, and a tap still picks the segment
/// (docs/presentation/scrub-pairing.md, "Which finger is whose").
///
/// Use it for every segmented choice that sits inside a vertical scroll — which, in this app,
/// is every one (forms and lists scroll too). VoiceOver and UI tests see the native control:
/// the row's accessibility representation *is* a segmented `Picker`, so it reads as one
/// ("Both, selected, 1 of 3") and adjusts like one.
struct SegmentRow<Value: Hashable>: View {
    private let title: String
    @Binding private var selection: Value
    private let options: [Value]
    private let label: (Value) -> String

    @Environment(\.isEnabled) private var isEnabled
    @Namespace private var thumb

    /// - Parameters:
    ///   - title: what the choice is about; VoiceOver's label, never drawn (a segment row
    ///     carries its question in the words around it, as `.labelsHidden()` did).
    ///   - options: the segments, left to right.
    ///   - label: each segment's word.
    init(_ title: String, selection: Binding<Value>, options: [Value],
         label: @escaping (Value) -> String) {
        self.title = title
        self._selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.snappy(duration: 0.2), value: selection)
        .accessibilityRepresentation {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func segment(_ option: Value) -> some View {
        let selected = option == selection
        return Button {
            guard option != selection else { return }
            selection = option
        } label: {
            Text(label(option))
                .font(.subheadline.weight(selected ? .semibold : .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 30)
                .padding(.vertical, 2)
                .background {
                    if selected {
                        Capsule()
                            .fill(Self.thumbFill)
                            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// White on the light track, a lifted grey on the dark one — the native thumb's two inks.
    private static var thumbFill: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.39, alpha: 1)
                : .white
        })
    }
}
