import SwiftUI

/// **What a text field looks like when the app draws it on a surface of its own.**
///
/// The bug this exists for (Jan, release candidate 58, dark mode): the intervals.icu key
/// field on the first-run setup card rendered as a solid black bar. It was a `SecureField`
/// with `.textFieldStyle(.roundedBorder)`, and `.roundedBorder` fills itself with
/// `systemBackground` — pure black in dark mode — while the card it sits on is
/// `secondarySystemBackground`, a near-black grey. Two almost-identical blacks with a
/// hairline between them is a bar, not a field: there was nothing to tell the rider where to
/// tap, and an empty secure field has no dots to give the game away either. In light mode
/// the same two tokens are white on light grey, which is why it only ever looked wrong on
/// half the phones.
///
/// So the app stops borrowing a system style whose contrast depends on which background it
/// happens to land on, and paints the field itself:
///
/// * a `tertiarySystemGroupedBackground` fill, which is a step *lighter* than the card in
///   dark mode (#2C2C2E on #1C1C1E) and a step *darker* than it in light (#F2F2F7 on white)
///   — a field that reads as inset either way round, on a card or on a plain sheet;
/// * a hairline `separator` border, so it is still a field on a surface that matches the
///   fill (a plain white sheet in light mode, where fill alone would say nothing);
/// * explicit `.primary` text and an accent-coloured caret, rather than whatever foreground
///   style the enclosing card happened to set.
///
/// Every field the app draws outside a `Form` or `List` row uses it. Fields *inside* a form
/// row are left alone on purpose: there the row is the field's background and the system
/// already gets the contrast right in both themes.
private struct AppTextFieldChrome: ViewModifier {
    /// Matches the 18 pt-padded cards these fields sit on.
    private let corner: CGFloat = 10

    func body(content: Content) -> some View {
        content
            // `.plain` and not `.roundedBorder`: the whole point is that the chrome below
            // is ours, and two borders is a field inside a field.
            .textFieldStyle(.plain)
            .foregroundStyle(.primary)
            .tint(Color.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: corner))
            .overlay {
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(Color(.separator), lineWidth: 1)
            }
    }
}

extension View {

    /// The app's own text-field chrome — see `AppTextFieldChrome`. For a `TextField` or
    /// `SecureField` the app draws on a card or a sheet of its own; fields inside a `Form`
    /// or `List` row keep the system's.
    func appTextFieldChrome() -> some View {
        modifier(AppTextFieldChrome())
    }
}
