import Foundation

/// **Where this recording came from**, as one short line under the date on the session page.
///
/// `SessionRow.importSource` is a `+`-joined *set*: a session the watch app handed over and a
/// later sync also saw reads `"applewatch+icu"`. Only one of them is worth a line, and it is
/// the one nearest the water — the app that made the recording beats the account it later
/// travelled through. `order` is that ladder, and it is the only place it is written down.
///
/// The words are `ImportSource.libraryFilterLabel`, so the line under the date and the chip
/// in the filter menu say the same thing about the same session. One exception, spelled out
/// because "Apple Watch" alone is ambiguous in this app: a recording the CleanJibe watch app
/// made says so.
public enum SessionProvenance {

    /// Nearest the water first. A door not on this list has no line, which is the honest
    /// answer for a session whose column was never written.
    static let order: [ImportSource] = [
        .appleWatch, .watchDirect, .watch, .appleHealth, .strava, .icu, .gdpr, .airdrop,
        .file, .example, .fixtures,
    ]

    /// "Apple Watch · CleanJibe", "intervals.icu", "Strava", "Apple Health", "File".
    /// Nil when the column names nothing this build knows.
    public static func line(importSource: String?) -> String? {
        guard let source = order.first(where: { $0.isNamed(in: importSource) }) else {
            return nil
        }
        return label(source)
    }

    /// **The line for one row**: the door, and where a direct transfer stopped part way,
    /// that too (schema v21, docs/transfer-format.md §5). "Garmin watch, direct · part of it"
    /// — the same three words Settings → Garmin watch puts beside that transfer, so the two
    /// places say one thing. The session's own numbers are what arrived; the help topic on
    /// the direct transfer says what "part of it" means.
    public static func line(for row: SessionRow) -> String? {
        guard let line = line(importSource: row.importSource) else { return nil }
        guard row.transferCutShort == true,
              order.first(where: { $0.isNamed(in: row.importSource) }) == .watchDirect
        else { return line }
        return line + " · " + cutShortMark
    }

    /// What a cut-short direct transfer is called, on the session and in Settings.
    public static let cutShortMark = "part of it"

    /// The door in the rider's words. `.appleWatch` is the one that needs two: the app that
    /// recorded it, after the wrist it was recorded on.
    public static func label(_ source: ImportSource) -> String {
        switch source {
        case .appleWatch: ImportSource.appleWatch.libraryFilterLabel + " · " + Branding.appName
        default: source.libraryFilterLabel
        }
    }
}
