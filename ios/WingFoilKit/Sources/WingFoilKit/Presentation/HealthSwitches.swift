import Foundation

/// **Settings → Apple Health: both directions, both always on the screen**
/// (docs/review-checklist.md, pattern E/G).
///
/// The second switch used to appear only once a workout had actually come in that way, so a
/// rider who wanted the pickup armed *before* his first import was told nothing and shown
/// nothing. State that has to survive a launch is a positive flag, and a door is never
/// argued out of existence by what the rider has not done yet. Both switches are drawn in
/// every build that has the section, and what the rider has done changes the footer instead.
///
/// One wording per switch, wherever the switch is offered: the automatic pickup is on this
/// list and on Import → Apple Health, and those are two places showing one control.
public enum HealthSwitch: String, CaseIterable, Sendable, Identifiable {

    /// Out of CleanJibe, into Health.
    case write
    /// Out of Health, into CleanJibe, without being asked each time.
    case autoImport

    public var id: String { rawValue }

    /// The order the section draws them: what leaves first, what arrives second.
    public static let ordered: [HealthSwitch] = [.write, .autoImport]

    public var title: String {
        switch self {
        case .write: "Add sessions to Apple Health"
        case .autoImport: "Import new Health workouts automatically"
        }
    }

    /// **What you get, in one line** (pattern K). The mechanism is the help topic.
    public var footer: String {
        switch self {
        case .write:
            "Each session is added to Apple Health as a Surfing workout. A session you "
            + "imported from Health is left alone."
        case .autoImport:
            "New Health workouts are picked up when you open CleanJibe. It takes only "
            + "the types you chose on the Import screen."
        }
    }

    /// The topic that answers *how*.
    public var helpTopic: HelpTopicID {
        switch self {
        case .write: .privacy
        case .autoImport: .appleWorkoutApp
        }
    }
}
