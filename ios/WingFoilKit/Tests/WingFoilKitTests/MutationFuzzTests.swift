import Foundation
import Testing
@testable import WingFoilKit

/// **Corrupt the corpus on purpose, and see what the importer does with it.**
///
/// `SyncCrashHuntTests` asks named questions — what about a session with one record, what
/// about a lap of zero duration. This asks no question at all: it takes the recordings the
/// engine was built on, flips bytes in them, and requires that every mutant either parses or
/// throws, and that none of them takes the process down. It is the only way to reach the
/// shapes nobody thought of, which is the whole category the first sync from a stranger's
/// account lands in.
///
/// Two families, because they test different doors:
///
/// * **damaged** — bytes flipped and the file's CRC left as it was. Every one of these must
///   be *refused*: a FIT whose checksum does not match is damaged, and handing damaged bytes
///   to the vendored C decoder segfaults the process (this fuzz is how that was found — see
///   `FitSessionParser.checkReadable`).
/// * **repaired** — the same flips with the CRC recomputed, so the file is well-formed and
///   merely strange. These reach the decoder, the developer-field reader and the analyzer,
///   and are the ones that stand in for a recording written by a device nobody here owns.
///
/// Seeded, so any mutant that kills the suite is reproducible from the seed. `FUZZ_MUTANTS`
/// raises the per-file budget for a deliberate hunt (a few thousand is minutes);
/// `FUZZ_TRACE=1` prints each attempt before it runs, which is the only trace left when a
/// mutant crashes rather than fails.
@Suite struct MutationFuzzTests {

    /// A tiny deterministic PRNG — the seed is the whole reproduction recipe.
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = (seed &* 6_364_136_223_846_793_005 &+ 1) | 1 }
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    /// Mutants per source file. Six is a *regression* budget — ninety-six mutants a family
    /// over the corpus, about a minute in `swift test`, enough that a reopened hole is caught
    /// on the next run. A hunt wants three orders of magnitude more, which is what
    /// `FUZZ_MUTANTS` is for.
    static var budget: Int {
        Int(ProcessInfo.processInfo.environment["FUZZ_MUTANTS"] ?? "") ?? 6
    }

    private static let trace = ProcessInfo.processInfo.environment["FUZZ_TRACE"] == "1"

    /// A damaged recording is refused, every time, before anything reads its records.
    @Test func damagedRecordingsAreRefused() throws {
        var mutants = 0, parsed = 0
        for url in Self.fitSources() {
            let original = try Data(contentsOf: url)
            for seed in 0..<Self.budget {
                var rng = Self.generator(for: url, seed: seed)
                let data = Self.mutate(original, using: &rng, repairCRC: false)
                Self.note(url, seed, "damaged")
                mutants += 1
                if (try? TrackParser.parse(data: data)) != nil { parsed += 1 }
            }
        }
        print("fuzz damaged \(mutants): \(parsed) slipped through")
        #expect(mutants > 0)
        #expect(parsed == 0, "\(parsed) damaged recordings reached the decoder")
    }

    /// A well-formed recording with strange content is read, or refused — never fatal.
    @Test func repairedMutantsNeverTrap() throws {
        var mutants = 0, parsed = 0, analysed = 0, threw = 0
        for url in Self.fitSources() {
            let original = try Data(contentsOf: url)
            for seed in 0..<Self.budget {
                var rng = Self.generator(for: url, seed: seed)
                let data = Self.mutate(original, using: &rng, repairCRC: true)
                Self.note(url, seed, "repaired")
                mutants += 1
                do {
                    let track = try TrackParser.parse(data: data)
                    parsed += 1
                    // **The parser sees every mutant; the analyzer sees the session-shaped
                    // ones.** A flip in a timestamp can leave a track that is still inside
                    // the importer's week-long ceiling and is nonetheless four days of two
                    // samples — and the rolling-rate series over four days is a minute of
                    // arithmetic per mutant, which would put this suite out of reach of
                    // `swift test`. The ceilings that make those safe have named tests of
                    // their own (`aBrokenClockIsRefusedByTheImporter`); what this family is
                    // hunting is a trap in the *front end*, and that has already fired.
                    guard Self.sessionShaped(track), Self.analyses(seed: seed) else { continue }
                    analysed += 1
                    _ = SessionSummarizer.analyze(track)
                } catch {
                    threw += 1
                }
            }
        }
        print("fuzz repaired \(mutants): \(parsed) parsed (\(analysed) analysed), \(threw) refused")
        #expect(mutants > 0)
        #expect(parsed > 0, "every repaired mutant was refused — the mutation is too blunt")
    }

    // MARK: - Machinery

    /// **Which mutants get analysed.** Every one is *parsed* — that is where both front-end
    /// traps were, and a parse is a fraction of a second. A full analysis is ~2.7 s on a
    /// corpus-sized file, so analysing all ninety-six would cost four minutes and make this
    /// suite something people skip. One mutant per source file keeps the analyzer in the
    /// loop at a twelfth of the price; `FUZZ_DEEP=1` analyses every one, which is what a
    /// deliberate hunt wants alongside `FUZZ_MUTANTS`.
    private static let deep = ProcessInfo.processInfo.environment["FUZZ_DEEP"] == "1"

    static func analyses(seed: Int) -> Bool { deep || seed == 0 }

    /// Does this mutant still look like an afternoon? Four hours, which every recording in
    /// the corpus is well inside and no timestamp flip survives. Deliberately far tighter
    /// than the importer's own week-long ceiling: this is a budget, not a rule.
    static let analysisSpanS: Double = 4 * 3600

    static func sessionShaped(_ track: RawTrack) -> Bool {
        guard let first = track.samples.first, let last = track.samples.last else { return false }
        let duration = last.t - first.t
        return duration.isFinite && duration >= 0 && duration <= analysisSpanS
    }

    /// **One recording per corpus family, not all sixteen.**
    ///
    /// `fixtures/sessions` holds ten native Garmin windsurf files written by the same watch
    /// in the same fortnight; mutating all ten asks the same question ten times at a second
    /// of parse each. One per directory — native, CIQ, other-apps, synthetic — keeps every
    /// *shape* the corpus has while putting the suite back inside `swift test`. `FUZZ_ALL=1`
    /// takes the lot, which is what a deliberate hunt wants.
    static func fitSources() -> [URL] {
        let all = allFixtureTracks().filter { $0.pathExtension.lowercased() == "fit" }
        guard ProcessInfo.processInfo.environment["FUZZ_ALL"] != "1" else { return all }
        var seen: Set<String> = []
        return all.filter { seen.insert($0.deletingLastPathComponent().lastPathComponent).inserted }
    }

    /// Stable across runs and machines: `hashValue` is neither.
    static func generator(for url: URL, seed: Int) -> Seeded {
        let salt = url.lastPathComponent.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return Seeded(seed: salt &+ UInt64(seed))
    }

    static func note(_ url: URL, _ seed: Int, _ family: String) {
        guard trace else { return }
        print("fuzz trying \(family) \(url.lastPathComponent) seed \(seed)")
        fflush(stdout)
    }

    /// One mutant: a handful of byte flips inside the **data section**, so the file still
    /// announces itself as a FIT of the right length and the mutation lands where the
    /// content is read. With `repairCRC`, the trailing checksum is recomputed afterwards,
    /// which is what turns "damaged" into "unusual".
    static func mutate(_ data: Data, using rng: inout Seeded, repairCRC: Bool) -> Data {
        var bytes = [UInt8](data)
        guard let layout = FitStreamWalker.layout(of: bytes),
              layout.dataEnd > layout.headerSize + 8,
              layout.dataEnd + 2 <= bytes.count
        else { return data }

        let flips = Int.random(in: 1...8, using: &rng)
        for _ in 0..<flips {
            let i = Int.random(in: layout.headerSize..<layout.dataEnd, using: &rng)
            bytes[i] ^= UInt8(truncatingIfNeeded: Int.random(in: 1...255, using: &rng))
        }
        if repairCRC {
            let crc = FitStreamWalker.crc16(bytes[0..<layout.dataEnd])
            bytes[layout.dataEnd] = UInt8(crc & 0xFF)
            bytes[layout.dataEnd + 1] = UInt8(crc >> 8)
        }
        return Data(bytes)
    }
}
