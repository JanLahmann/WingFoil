import Foundation
import WidgetKit

/// Nudges the home-screen widgets after the library changes.
///
/// Separated from the store so the call site does not have to care whether a widget
/// extension is installed at all: `WidgetCenter` is part of the system framework, and
/// asking it to reload timelines when nothing is on a home screen is a no-op.
enum WidgetRefresher {

    /// A no-op in the release channel, which embeds no widget extension (docs/channels.md).
    /// The call sites stay unconditional — nudging a widget that is not there was always
    /// free — but the binary should not carry the call either.
    static func reloadTimelines() {
        #if BETA && !targetEnvironment(macCatalyst)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
