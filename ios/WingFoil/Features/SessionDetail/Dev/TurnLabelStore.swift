import Foundation
import Observation
import WingFoilKit

// **Dev build only** — see `DevWorkbench`. The public build cannot write a label and cannot
// read one: this file is not compiled into it.
#if TUNING

/// **Where the rider's own verdicts live** — one small Codable sidecar per session, in the
/// app's preferences, next to the map-layer sets and the replay settings.
///
/// **Not in the analysis, and not in the archive.** `analysis.json` is the engine's account of
/// a recording and is thrown away and rebuilt whenever the engine or the tuning moves; a label
/// is the *rider's* account and must survive every one of those sweeps. Putting it in the
/// document would also make it an input the engine could, one refactor later, read — and the
/// entire value of a ground truth is that the thing being judged cannot see it.
///
/// **One key for the whole library**, `turnLabels.v1`, holding `[sessionID: TurnLabelSheet]`.
/// A key per session would be tidier to write and impossible to *enumerate*, and enumeration is
/// the whole of Settings → Tuning → Labels: it has to score every session the rider has ever
/// labelled without knowing which those are. The payload is a few hundred bytes per labelled
/// session, which is the size of a preference and not of a database.
@MainActor
@Observable
final class TurnLabelStore {

    static let shared = TurnLabelStore()

    static let key = "turnLabels.v1"

    /// Every sheet, keyed by session id. Written back on every change, whole — a label is a
    /// once-a-turn action and the map is tiny.
    private(set) var sheets: [String: TurnLabelSheet]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sheets = Self.load(from: defaults)
    }

    // MARK: - Reading

    func sheet(for sessionID: String) -> TurnLabelSheet {
        sheets[sessionID] ?? TurnLabelSheet(sessionID: sessionID)
    }

    func label(sessionID: String, turnIndex: Int) -> TurnLabel? {
        sheets[sessionID]?[turnIndex]
    }

    /// Ids of every session carrying at least one label — what the scoring page loads.
    var labelledSessionIDs: [String] {
        sheets.filter { !$0.value.isEmpty }.keys.sorted()
    }

    var totalLabels: Int { sheets.values.reduce(0) { $0 + $1.count } }

    // MARK: - Writing

    /// Sets or clears one turn's label. Clearing the last label on a session drops the sheet
    /// rather than leaving an empty one behind, so `labelledSessionIDs` never lists a session
    /// with nothing to score.
    func set(_ label: TurnLabel?, sessionID: String, turnIndex: Int) {
        var sheet = self.sheet(for: sessionID)
        sheet[turnIndex] = label
        if sheet.isEmpty {
            sheets[sessionID] = nil
        } else {
            sheets[sessionID] = sheet
        }
        save()
    }

    func clear(sessionID: String) {
        sheets[sessionID] = nil
        save()
    }

    func clearAll() {
        sheets = [:]
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sheets) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private static func load(from defaults: UserDefaults) -> [String: TurnLabelSheet] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: TurnLabelSheet].self, from: data)
        else { return [:] }
        return decoded
    }
}

#endif
