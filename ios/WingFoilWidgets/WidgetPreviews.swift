import SwiftUI
import WidgetKit

/// Sample snapshots — the gallery placeholder, and one per state Jan has to be able to look
/// at in Xcode without waiting for a week of bad wind.
///
/// Real-looking numbers everywhere, so a widget never advertises itself as a row of dashes.
extension WidgetSnapshot {

    /// The gallery placeholder: a good afternoon, two days ago.
    static var preview: WidgetSnapshot {
        var snapshot = WidgetSnapshot(
            generatedAt: .now,
            lastSession: LastSession(id: "preview", title: "Nago Torbole", date: .now,
                                     foilPct: 62, best2sKn: 21.43, flightCount: 23,
                                     durationS: 5400, flewThrough: 9, touchdown: 9,
                                     fellIn: 12, track: .previewTrack),
            weeklyFoilMinutes: 214, weeklySessions: 3, weeklyHours: 5.6,
            recent: [Day(date: .now.addingTimeInterval(-86_400), foilMinutes: 96, hours: 2.1),
                     Day(date: .now.addingTimeInterval(-3 * 86_400), foilMinutes: 62,
                         hours: 1.8),
                     Day(date: .now.addingTimeInterval(-5 * 86_400), foilMinutes: 56,
                         hours: 1.7)],
            season: Season(label: "2026/27", sessions: 18, foilHours: 22.4, cleanJibes: 96))
        snapshot.bests = Self.previewBests
        snapshot.facts = Self.previewFacts
        return snapshot
    }

    /// A fortnight of wrong wind: the same library, nothing ridden in the last seven days.
    static var previewDryWeek: WidgetSnapshot {
        var snapshot = Self.preview
        let lastRidden = Date.now.addingTimeInterval(-12 * 86_400)
        snapshot.lastSession?.date = lastRidden
        snapshot.recent = []
        snapshot.weeklyFoilMinutes = 0
        snapshot.weeklySessions = 0
        snapshot.weeklyHours = 0
        return snapshot
    }

    static var previewBests: [Fact] {
        let spot = "Nago Torbole"
        return [Fact(kind: .best2s, value: 24.13, spot: spot,
                     date: .now.addingTimeInterval(-40 * 86_400), scope: .allTime),
                Fact(kind: .longestFlight, value: 372, spot: "Rheinstetten",
                     date: .now.addingTimeInterval(-75 * 86_400), scope: .allTime),
                Fact(kind: .bestJph, value: 14.2, spot: spot,
                     date: .now.addingTimeInterval(-40 * 86_400), scope: .allTime)]
    }

    /// One per day, in the order the rotation walks them.
    static var previewFacts: [Fact] {
        [Fact(kind: .best2s, value: 24.13, spot: "Nago Torbole",
              date: .now.addingTimeInterval(-40 * 86_400), scope: .season),
         Fact(kind: .longestFlight, value: 372, spot: "Rheinstetten",
              date: .now.addingTimeInterval(-75 * 86_400), scope: .season),
         Fact(kind: .bestJph, value: 14.2, spot: "Nago Torbole",
              date: .now.addingTimeInterval(-40 * 86_400), scope: .season),
         Fact(kind: .longestDryStreak, value: 17, spot: "Fehmarn",
              date: .now.addingTimeInterval(-20 * 86_400), scope: .season),
         Fact(kind: .onThisDay, value: 11, spot: "Nago Torbole",
              date: .now.addingTimeInterval(-2 * 365 * 86_400), scope: .allTime,
              yearsAgo: 2, best2sKn: 24.1, flights: 11)]
    }
}

extension WidgetSnapshot.Track {

    /// Eight reaches up and down a lake, the shape a wingfoil afternoon actually makes.
    static var previewTrack: WidgetSnapshot.Track {
        var xy: [Double] = []
        let legs = 8
        let perLeg = 18
        for leg in 0..<legs {
            for step in 0...perLeg {
                let along = Double(step) / Double(perLeg)
                let x = leg.isMultiple(of: 2) ? along : 1 - along
                let y = Double(leg) / Double(legs - 1) * 0.7 + 0.15
                    + sin(along * .pi * 2) * 0.02
                xy.append(min(max(x * 0.94 + 0.03, 0), 1))
                xy.append(min(max(y, 0), 1))
            }
        }
        let xs = xy.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
        let ys = xy.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element)
        return WidgetSnapshot.Track(xy: xy, minX: xs.min() ?? 0, minY: ys.min() ?? 0,
                                    maxX: xs.max() ?? 1, maxY: ys.max() ?? 1, spanM: 2400)
    }
}

extension SnapshotEntry {
    static func sample(_ snapshot: WidgetSnapshot?, unreachable: Bool = false) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: snapshot, unreachable: unreachable)
    }
}

// MARK: - Last session

#Preview("Last session · small", as: .systemSmall) {
    LastSessionWidget()
} timeline: {
    SnapshotEntry.sample(.preview)
    SnapshotEntry.sample(nil)
}

#Preview("Last session · medium", as: .systemMedium) {
    LastSessionWidget()
} timeline: {
    SnapshotEntry.sample(.preview)
    SnapshotEntry.sample(nil)
}

#Preview("Last session · large", as: .systemLarge) {
    LastSessionWidget()
} timeline: {
    SnapshotEntry.sample(.preview)
    SnapshotEntry.sample(nil)
}

// MARK: - This week

#Preview("This week · small", as: .systemSmall) {
    WeeklyFoilWidget()
} timeline: {
    SnapshotEntry.sample(.preview)            // a week that happened
    SnapshotEntry.sample(.previewDryWeek)     // a week that did not
    SnapshotEntry.sample(nil)                 // no library
}

#Preview("This week · medium", as: .systemMedium) {
    WeeklyFoilWidget()
} timeline: {
    SnapshotEntry.sample(.preview)
    SnapshotEntry.sample(.previewDryWeek)
    SnapshotEntry.sample(nil)
}

/// The rotation, one entry per day — the same snapshot drawn on five consecutive days, so
/// the five facts can be stepped through in the preview the way a rider meets them.
#Preview("Since your last session · the rotation", as: .systemMedium) {
    WeeklyFoilWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .previewDryWeek, unreachable: false)
    SnapshotEntry(date: .now.addingTimeInterval(86_400), snapshot: .previewDryWeek,
                  unreachable: false)
    SnapshotEntry(date: .now.addingTimeInterval(2 * 86_400), snapshot: .previewDryWeek,
                  unreachable: false)
    SnapshotEntry(date: .now.addingTimeInterval(3 * 86_400), snapshot: .previewDryWeek,
                  unreachable: false)
    SnapshotEntry(date: .now.addingTimeInterval(4 * 86_400), snapshot: .previewDryWeek,
                  unreachable: false)
}

// MARK: - Personal bests

#Preview("Personal bests · small", as: .systemSmall) {
    PersonalBestsWidget()
} timeline: {
    SnapshotEntry.sample(.preview)
    SnapshotEntry.sample(nil)
}

#Preview("Personal bests · medium", as: .systemMedium) {
    PersonalBestsWidget()
} timeline: {
    SnapshotEntry.sample(.preview)
    SnapshotEntry.sample(nil)
}

// MARK: - Not set up yet

#Preview("No app group", as: .systemMedium) {
    LastSessionWidget()
} timeline: {
    SnapshotEntry.sample(nil, unreachable: true)
}
