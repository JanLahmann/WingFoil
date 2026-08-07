import Foundation
import SwiftUI
import WingFoilKit

/// Presentation helpers: names, badges and units. Spots and gear arrive in phase 4 —
/// until then a session is identified by its date and its source filename.
enum SessionDisplay {

    /// "2026-08-03-1440_nago-torbole-windsurfen_native.fit" → "Nago Torbole Windsurfen".
    static func title(_ row: SessionRow) -> String {
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

    /// a = our CIQ FIT (everything) · b = native Doppler FIT · c = degraded source.
    static func sourceClassNote(_ sourceClass: String) -> String {
        switch sourceClass {
        case "a": "Class a — WingFoil CIQ recording (developer fields present)"
        case "b": "Class b — device FIT with Doppler speed"
        default: "Class c — degraded source, records are uncertified"
        }
    }
}

enum Fmt {

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// 1 h 24 m / 47 m 12 s
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
