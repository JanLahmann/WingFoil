import CryptoKit
import Foundation
import Testing
@testable import WingFoilKit

/// The share scrub, held against `lab/tools/scrub_fit.py` **byte for byte**.
///
/// "Scrubbed" is a claim about a file the rider hands to a stranger, so it is not enough
/// that the Swift port removes roughly the same things: the two implementations have to
/// produce the identical file. The reference outputs are generated with
///
///     lab/.venv/bin/python lab/tools/scrub_fit.py \
///         fixtures/sessions/ciq/2026-08-30-1407_nago-torbole-windsurfen_ciq.fit OUT.fit
///     …same, with --drop-accel
///
/// and pinned here as SHA-256 digests rather than committed fixtures — a 1 MB file whose
/// only content is "identical to the input" and a 43 KB one are both dead weight in the
/// repo, and a digest fails just as loudly. Regenerate the digests with the two commands
/// above if the scrub rules ever change on the Python side.
@Suite struct FitShareFilterTests {

    /// The corpus fixture the digests below were taken from. It is *already scrubbed* — it
    /// shipped through the same tool — which makes it the sharpest input available: the
    /// plain variant must reproduce it exactly.
    private static let fixtureStem = "2026-08-30-1407_nago-torbole-windsurfen_ciq"

    /// `scrub_fit.py IN OUT` — 964 281 bytes.
    private static let pythonPlainSHA256 =
        "7eee8888c76649f2eb47bfa464bf92c62ad988a7469b6bf6378151599c7c6df6"
    /// `scrub_fit.py IN OUT --drop-accel` — 43 221 bytes.
    private static let pythonAccelDroppedSHA256 =
        "e641a4a88af78a66db0c53b959126c5a33f9eece2cc33fae4b5a5ec1ed5c7bf0"

    private func fixtureBytes() throws -> [UInt8] {
        let url = try #require(findFixtureFIT(stem: Self.fixtureStem),
                               "fixtures/sessions/ciq/\(Self.fixtureStem).fit is missing")
        return [UInt8](try Data(contentsOf: url))
    }

    private func sha256(_ bytes: [UInt8]) -> String {
        SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
    }

    /// The whole point of the port, both variants at once.
    @Test func scrubMatchesThePythonToolByteForByte() throws {
        let input = try fixtureBytes()

        let plain = try #require(FitShareFilter.filter(input, dropAccel: false))
        #expect(plain.count == 964_281)
        #expect(sha256(plain) == Self.pythonPlainSHA256,
                "the plain scrub diverged from lab/tools/scrub_fit.py")

        let compact = try #require(FitShareFilter.filter(input, dropAccel: true))
        #expect(compact.count == 43_221)
        #expect(sha256(compact) == Self.pythonAccelDroppedSHA256,
                "the --drop-accel scrub diverged from lab/tools/scrub_fit.py")
    }

    /// The corpus fixture went through the tool already, so scrubbing it again must change
    /// nothing at all. An idempotence failure is the cheapest possible signal that the
    /// rewrite is perturbing framing it only meant to copy.
    @Test func scrubbingAnAlreadyScrubbedFileIsAnIdentity() throws {
        let input = try fixtureBytes()
        #expect(FitShareFilter.filter(input, dropAccel: false) == input)
    }

    /// What the rewrite reports it did, on the file the digests come from: the two serial
    /// fields the watch writes, and — with `dropAccel` — the whole high-rate stream.
    @Test func theReportNamesWhatWasRemoved() throws {
        let input = try fixtureBytes()

        let plain = try #require(FitShareFilter.scrub(input, dropAccel: false))
        #expect(plain.report.patched["file_id.serial_number"] == 1)
        #expect(plain.report.patched["device_info.serial_number"] == 2)
        // Already scrubbed, so there is no personal message left to drop.
        #expect(plain.report.dropped.isEmpty)

        let compact = try #require(FitShareFilter.scrub(input, dropAccel: true))
        #expect(compact.report.dropped[FitShareFilter.accelerometerData] == 2580)
        #expect(compact.report.patched == plain.report.patched)
        #expect(compact.report.kept == plain.report.kept - 2580)
    }

    /// The scrub must survive the parser on the other side — a receiver's phone has to be
    /// able to open what we handed them — and the compact variant must cost nothing but
    /// the accelerometer stream: same flights, same turns, same records.
    @Test func bothVariantsReanalyzeToTheSameSession() throws {
        let input = try fixtureBytes()
        let before = try SessionSummarizer.analyze(FitSessionParser.parse(data:Data(input)))

        for dropAccel in [false, true] {
            let out = try #require(FitShareFilter.filter(input, dropAccel: dropAccel))
            let after = try SessionSummarizer.analyze(FitSessionParser.parse(data:Data(out)))
            let tag = dropAccel ? "--drop-accel" : "plain"
            // Flight *geometry*, not the whole record: `takeoffPumps` is a stroke count the
            // accelerometer produced, so the compact variant honestly reports nil for it.
            // That is the one number `--drop-accel` is allowed to cost, and the Python
            // tool's own `--verify` makes the same exemption.
            #expect(after.flights.map { [$0.startTs, $0.endTs, $0.distM, $0.maxKn] }
                    == before.flights.map { [$0.startTs, $0.endTs, $0.distM, $0.maxKn] },
                    "\(tag): flights moved")
            #expect(after.turns == before.turns, "\(tag): turns moved")
            #expect(after.flightEnds == before.flightEnds, "\(tag): flight ends moved")
            #expect(after.records == before.records, "\(tag): records moved")
            #expect(after.wind == before.wind, "\(tag): wind moved")
            // Only the capability the dropped stream provided may change.
            #expect(after.capabilities.hasAccel == !dropAccel)
        }
    }

    /// No serial number may survive on either channel. Asserted on the *bytes*, through the
    /// developer-field-free native reader, because the file is the thing being shared.
    @Test func noSerialNumberSurvives() throws {
        let scrubbed = try #require(FitShareFilter.filter(try fixtureBytes(), dropAccel: true))
        // file_id (global 0) field 3 and device_info (global 23) field 3, read back off the
        // record layer with the same walker the filter used.
        var offenders: [String] = []
        _ = FitStreamWalker.walk(scrubbed) { event in
            guard case let .data(_, def, range, payload) = event,
                  def.globalNum == 0 || def.globalNum == 23 else { return }
            for field in def.fields where field.num == 3 {
                let start = payload.lowerBound + field.offset
                let value = scrubbed[start..<(start + field.size)]
                if value.contains(where: { $0 != 0 }) {
                    offenders.append("global \(def.globalNum) at \(range.lowerBound)")
                }
            }
        }
        #expect(offenders.isEmpty, "a serial number survived: \(offenders)")
    }

    /// Fail-closed: anything we cannot walk and re-sign is refused outright rather than
    /// shared in whatever state we managed to get it into.
    @Test func aFileThatIsNotAWalkableFitIsRefused() {
        #expect(FitShareFilter.filter([UInt8]("not a FIT file at all".utf8),
                                      dropAccel: false) == nil)
        #expect(FitShareFilter.filter([], dropAccel: true) == nil)
    }

    /// A damaged file must not come back re-signed with a fresh, valid CRC: that would turn
    /// corruption we can see into corruption the receiver cannot.
    @Test func aFileFailingItsOwnCrcIsRefused() throws {
        var bytes = try fixtureBytes()
        bytes[bytes.count / 2] ^= 0xFF
        #expect(FitShareFilter.filter(bytes, dropAccel: false) == nil)
    }

    // MARK: - Naming

    @Test func shareFilenameIsReadableAndSafe() {
        let date = Date(timeIntervalSince1970: 1_788_048_000)   // 2026-08-30 UTC
        let utc = TimeZone(identifier: "UTC")!
        #expect(FitShareFilter.filename(date: date, title: "Torbole", timeZone: utc)
                == "2026-08-30-torbole.fit")
        // Spaces, punctuation and accents all reduce to one dash each; nothing that could
        // confuse a file system survives.
        #expect(FitShareFilter.filename(date: date, title: "Nago · Torbole (früh)",
                                        timeZone: utc)
                == "2026-08-30-nago-torbole-fruh.fit")
        // A title with nothing nameable in it still yields a legal filename.
        #expect(FitShareFilter.filename(date: date, title: "···", timeZone: utc)
                == "2026-08-30.fit")
        #expect(FitShareFilter.filename(date: date, title: String(repeating: "a", count: 90),
                                        timeZone: utc).count == "2026-08-30-".count + 40 + 4)
    }
}
