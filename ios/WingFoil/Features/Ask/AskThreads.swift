#if BETA
import Foundation

/// **Ask CleanJibe's conversations, kept on the phone** (Jan, 17 Oct 2026: "doesn't show
/// the history from right before"). One conversation per place: Help and the menu share
/// `help`, each session has its own. A file each in Application Support, never iCloud and
/// never sent anywhere; nothing new leaves the phone, because the Worker still sees only the
/// last five pairs a question carries anyway.
///
/// A conversation left alone for a day is dropped, so an old exchange does not come back
/// weeks later as if it were today's. *New conversation* drops it at once.
enum AskThreads {
    static let maxAge: TimeInterval = 24 * 3600

    struct Saved: Codable {
        var updated: Date
        var messages: [AskMessage]
    }

    static func key(session id: String) -> String { "session." + id }
    static let help = "help"

    private static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "Ask", directoryHint: .isDirectory)
    }

    private static func file(_ key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" }
        return folder.appending(path: String(safe) + ".json")
    }

    /// The conversation as it was left, an answer that never finished marked as interrupted.
    static func load(_ key: String, now: Date = .now) -> [AskMessage] {
        purgeStale(now: now)
        guard let data = try? Data(contentsOf: file(key)),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              now.timeIntervalSince(saved.updated) < maxAge else { return [] }
        return saved.messages.map { m in
            var m = m
            if !m.mine, !m.failed, m.answerId == nil {
                m.failed = true
                if m.text.isEmpty { m.text = AskMessage.interrupted }
            }
            return m
        }
    }

    static func save(_ key: String, _ messages: [AskMessage], now: Date = .now) {
        if messages.isEmpty { return clear(key) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Saved(updated: now, messages: messages)) else { return }
        try? data.write(to: file(key), options: [.atomic, .completeFileProtection])
    }

    static func clear(_ key: String) {
        try? FileManager.default.removeItem(at: file(key))
    }

    /// Every conversation older than a day, whichever place it belongs to.
    static func purgeStale(now: Date = .now) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for f in files {
            let modified = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) >= maxAge { try? fm.removeItem(at: f) }
        }
    }
}

/// One bubble of a conversation.
struct AskMessage: Identifiable, Codable {
    var id = UUID()
    var mine: Bool
    var text: String
    var answerId: String?
    var vote = 0
    var failed = false

    static let interrupted = "This answer was interrupted. Ask again."
}
#endif
