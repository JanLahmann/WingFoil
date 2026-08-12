import Foundation

/// The half of the widget snapshot that reads the library.
///
/// Split from `WidgetSnapshot.swift` so the widget extension can compile the *format*
/// without dragging GRDB and the FIT parser into an extension whose whole job is to decode
/// one small JSON blob. Only the app compiles this file.
extension WidgetSnapshot {

    /// Builds the snapshot from the library's summary rows.
    ///
    /// `titleForRow` is injected because a readable session name is presentation the app
    /// owns (spot name, then filename). `now` is a parameter so the weekly window is
    /// testable.
    public static func make(sessions: [SessionRow], now: Date = Date(),
                            titleForRow: (SessionRow) -> String) -> WidgetSnapshot {
        let sorted = sessions.sorted { $0.startDate < $1.startDate }
        var snapshot = WidgetSnapshot(generatedAt: now)

        if let latest = sorted.last {
            snapshot.lastSession = LastSession(
                id: latest.id,
                title: titleForRow(latest),
                date: latest.startDate,
                foilPct: latest.foilPct,
                best2sKn: latest.best2sKn,
                flightCount: latest.flightCount,
                durationS: latest.durationS,
                flewThrough: latest.turnsFlewThrough ?? 0,
                touchdown: latest.turnsTouchdown ?? 0,
                fellIn: latest.turnsFellIn ?? 0)
        }

        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let recent = sorted.filter { $0.startDate >= weekAgo && $0.startDate <= now }
        snapshot.weeklySessions = recent.count
        snapshot.weeklyHours = recent.reduce(0) { $0 + $1.durationS } / 3600
        // foilTimeS is a schema-v2 column; older rows fall back to the percentage, which
        // is the same quantity with a rounding error rather than a missing bar.
        snapshot.weeklyFoilMinutes = recent.reduce(0.0) { total, row in
            if let foilTimeS = row.foilTimeS { return total + foilTimeS / 60 }
            if let pct = row.foilPct { return total + row.durationS * pct / 100 / 60 }
            return total
        }
        return snapshot
    }
}
