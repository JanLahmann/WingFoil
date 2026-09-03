import Foundation

/// The one URL the watch app answers on, spelled once and compiled into both sides of it.
///
/// The complication writes it (`widgetURL`), the app reads it (`onOpenURL`), and a typo in
/// either would be a tap that silently does nothing — the exact failure a shared constant
/// costs one file to make impossible. The scheme is declared in the watch app's
/// `CFBundleURLTypes` in `ios/project.yml`.
///
/// `cleanjibe`, not the phone's `wingfoil-ciq`: that one is Garmin Connect Mobile's way back
/// to the iPhone and has nothing to do with a wrist.
enum WatchURL {
    static let scheme = "cleanjibe"
    static let startHost = "start"

    /// `cleanjibe://start` — force-unwrapped because a literal that fails to parse is a
    /// programmer error caught by the first run, not a condition to handle.
    static let start = URL(string: "\(scheme)://\(startHost)")!
}
