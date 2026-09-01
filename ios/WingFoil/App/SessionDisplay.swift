import Foundation
import SwiftUI
import WingFoilKit

/// Presentation helpers: names, badges and units. Spots and gear arrive in phase 4 —
/// until then a session is identified by its date and its source filename.
enum SessionDisplay {

    /// **The** name of a session: the rider's, if he has given it one, and the one derived
    /// from the recording's filename otherwise (`SessionNaming.title`).
    ///
    /// Every surface in the app already asked this function — the library row, the detail
    /// header, the share card, the clip's title card, the share messages, the shared file's
    /// own name, the widget, the records list, the map screen, the tombstone a delete leaves
    /// behind — which is exactly why the rename goes *here*. One mental model: you are naming
    /// the session, not decorating one export of it.
    static func title(_ row: SessionRow) -> String {
        SessionNaming.title(custom: row.customTitle, derived: derivedTitle(row))
    }

    /// "2026-08-03-1440_nago-torbole-windsurfen_native.fit" → "Nago Torbole Windsurfen".
    ///
    /// The fallback, and what a rider sees in the title field before he types: a guess made
    /// from how the watch happened to name the file, which is a good guess and never a
    /// statement.
    static func derivedTitle(_ row: SessionRow) -> String {
        guard let file = row.originalFilename else { return "Session" }
        var stem = (file as NSString).deletingPathExtension
        let parts = stem.split(separator: "_")
        if parts.count >= 2 { stem = String(parts[1]) }
        let words = stem.replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .filter { !($0.allSatisfy(\.isNumber) && $0.count >= 4) }
        guard !words.isEmpty else { return "Session" }
        return words.map { String($0.prefix(1)).uppercased() + String($0.dropFirst()) }
            .joined(separator: " ")
    }

    /// Discipline badge: the `discipline` developer field wins over the FIT sport code
    /// (docs/fit-schema.md — sport 43 alone does not mean wingfoil).
    static func badge(_ row: SessionRow) -> String {
        if let discipline = row.discipline?.trimmingCharacters(in: .whitespaces),
           !discipline.isEmpty {
            switch discipline.lowercased() {
            case "wingfoil": return "Wingfoil"
            case "windfoil": return "Windfoil"
            case "kitefoil": return "Kitefoil"
            default: return discipline.capitalized
            }
        }
        return sportLabel(row.sport)
    }

    static func sportLabel(_ sport: String?) -> String {
        switch (sport ?? "").lowercased() {
        case "windsurfing", "43": return "Windsurf"
        case "kitesurfing", "44": return "Kitesurf"
        case "sailing", "32": return "Sailing"
        case "stand_up_paddleboarding": return "SUP"
        case "walking", "11": return "CIQ app"
        case "": return "Unknown"
        default: return (sport ?? "Unknown").replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func badgeColor(_ row: SessionRow) -> Color {
        row.discipline?.isEmpty == false ? .teal : .blue
    }

    /// The word on the "this is not your session" capsule, or nil for a real import.
    /// Deliberately a separate badge from the discipline one: the reader has to be able to
    /// see *both* "wingfoil" and "borrowed" at a glance (docs/testing.md, example session).
    static func exampleBadge(_ row: SessionRow) -> String? {
        row.isExample ? "EXAMPLE" : nil
    }

    /// Said in full under the badge on the detail page, because "this one does not count
    /// towards your records" is the consequence a rider has to be told once rather than
    /// left to infer from a colour.
    static func riderNote(_ row: SessionRow) -> String? {
        row.rider.map {
            "\($0)'s session, shared with you — kept out of your records, trends and gear "
            + "totals."
        }
    }

    /// The line under a row that arrived over Bluetooth and has no recording yet. Said in
    /// full words rather than hinted at with a colour, because "these numbers came from
    /// the watch and will be replaced" is not something a rider can be expected to infer
    /// from a badge — and the numbers on the row look exactly like any other session's.
    static func provisionalNote(_ row: SessionRow) -> String? {
        row.isProvisional ? "From your watch — the recording has not synced yet" : nil
    }

    /// The line under the source badge on the session page.
    ///
    /// The engine's letters (`a` = a CleanJibe CIQ FIT, `b` = a native Doppler FIT,
    /// `c` = a degraded source) are the argument to this function and stay all over the
    /// fixtures, the golden files and `SessionRow.sourceClass`. They do not survive onto
    /// the screen: "Class b"
    /// names a bucket in someone else's taxonomy, and the rider's question is what he can
    /// and cannot see on this session. The `?` beside it opens `.sourceClass`, which answers
    /// the same question at length.
    static func sourceClassNote(_ sourceClass: String) -> String {
        switch sourceClass {
        case "a": "Recorded with the CleanJibe watch app — all metrics available"
        case "b": "Standard Garmin recording — everything except pump and takeoff effort"
        default: "No speed channel in this file — speed records are uncertified"
        }
    }
}

/// The "this session is on loan" capsule. Amber and upper-case rather than another tinted
/// discipline pill, because it is not a category — it is a disclaimer, and it has to read
/// as one at thumbnail size in a list of the rider's own sessions.
struct ExampleBadge: View {
    var text = "EXAMPLE"
    var font: Font = .caption2

    var body: some View {
        Text(text)
            .font(font.weight(.bold))
            .tracking(0.5)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.18), in: .capsule)
            .foregroundStyle(Color.orange)
            .accessibilityLabel("Example session, not your data")
    }
}

/// The "this is somebody else's session" capsule.
///
/// A third colour rather than a reuse of the example badge's amber: the two say different
/// things. The example is a demonstration nobody rode; this is a real session a real person
/// rode, just not the reader — and the name is the whole point, so the badge carries it
/// rather than a word like "SHARED". It reads at row size in a list of the rider's own
/// sessions, which is the only place it has to work.
struct RiderBadge: View {
    let name: String
    var font: Font = .caption2

    var body: some View {
        Label(name, systemImage: "person.crop.circle")
            .font(font.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.purple.opacity(0.16), in: .capsule)
            .foregroundStyle(Color.purple)
            .accessibilityLabel("\(name)'s session, not counted in your records")
    }
}

/// The "waiting for the recording" capsule. Blue and lower-key than the example badge:
/// this session IS the rider's, so it is not a disclaimer, it is a progress note.
struct ProvisionalBadge: View {
    var body: some View {
        Label("WATCH", systemImage: "antenna.radiowaves.left.and.right")
            .font(.caption2.weight(.bold))
            .tracking(0.5)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(0.16), in: .capsule)
            .foregroundStyle(Color.blue)
            .accessibilityLabel("Sent by your watch, recording not synced yet")
    }
}

enum Fmt {

    /// "Sun 30 Aug, 14:07" — **in the zone you name**.
    ///
    /// The zone is required and has no default, which is the whole point of it. It used to
    /// be the device's, implicitly, at every call site: a session's clock was formatted in
    /// whatever zone the *reader* happened to be in, which is right only while the two
    /// agree and silently wrong after every DST change and on every trip. A required
    /// parameter turns that into a question the compiler asks once per call site, and each
    /// one answers it out loud — `row.displayZone` for a session, `.current` (with a
    /// comment) for a surface that really is about the reader's own clock.
    static func date(_ date: Date, zone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime
            .weekday(.abbreviated).day().month(.abbreviated).hour().minute()
        style.timeZone = zone
        return date.formatted(style)
    }

    /// "30 Aug 2026", in the zone you name — see `date(_:zone:)`.
    static func shortDate(_ date: Date, zone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        style.timeZone = zone
        return date.formatted(style)
    }

    /// 1 h 24 m / 47 m 12 s
    ///
    /// The *long* spelling, for captions and sentences ("about 41 s of video", "6 m 12 s
    /// flying"). The key-metrics block and the share card use `KeyMetrics.duration`
    /// instead, which is the colon form both platforms have to agree on.
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        if h > 0 { return "\(h) h \(m) m" }
        if m > 0 { return "\(m) m \(s) s" }
        return "\(s) s"
    }

    /// mm:ss for chart axes.
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func km(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f km", value)
    }

    static func kn(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f kn", value)
    }

    static func pct(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", value)
    }

    static func meters(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value >= 1000 ? String(format: "%.2f km", value / 1000)
                             : String(format: "%.0f m", value)
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
