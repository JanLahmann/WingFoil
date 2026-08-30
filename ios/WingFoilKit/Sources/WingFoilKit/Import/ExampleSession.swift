import Foundation

/// The session shipped inside the app so a brand-new install has something to explore.
///
/// A first run is otherwise a wall: no sessions, no intervals.icu key, and no way to see
/// what any of the screens are *for* without going sailing first. This is one real
/// recording — Lake Garda, Nago-Torbole, an afternoon Ora — donated by the author and
/// scrubbed of every identifier (`lab/tools/scrub_fit.py --drop-accel`): the watch serial
/// number is zeroed in `file_id` and `device_info`, and the `user_profile`,
/// paired-accessory and Garmin-private lifetime-totals messages are removed outright.
///
/// The same pass also drops the 100 Hz `accelerometer_data` stream, which was 96 % of the
/// 10.5 MB original and would have been 96 % of the download. What ships is 445 KB and
/// still every byte a survivor of the original — no re-encode. The cost is deliberate and
/// bounded: the example degrades exactly the way a native-Windsurf recording does, so the
/// pump and takeoff-stroke figures read as absent rather than as zero (`hasAccel` is
/// false, `totalPumpStrokes` is nil), and the four turns whose touchdown was only visible
/// in the pump trace are classified `flewThrough`. Flights, distance, foil time, records,
/// wind, laps, heart rate and every turn count are bit-for-bit what the full file gives.
///
/// It is still a class-(a) recording — the developer fields and watch laps are all there —
/// so the example exercises the dev-field, lap, heart-rate and wind-estimate paths, and
/// the GPS track is long enough for the wind-axis estimate to be confident.
///
/// A session imported from here is flagged `isExample` and is deliberately **not** the
/// rider's data: it never enters Records or Trends (see `LibraryStore.clause`). It is
/// deletable like any other session, and the setup card offers to load it again.
public enum ExampleSession {

    /// The name the library shows. `SessionDisplay.title` reads the middle `_`-separated
    /// component, so this is what becomes "Nago Torbole Wingfoil" in the list.
    public static let filename = "2026-08-29-1440_nago-torbole-wingfoil_example.fit"

    /// Where the recording is from, for the card and the help topic.
    public static let place = "Nago-Torbole, Lake Garda"

    /// One line under the button: what the rider gets by tapping it.
    ///
    /// Every number here is one the library row and the detail page actually show, so the
    /// promise and the screen cannot disagree — a blurb quoting a duration the row
    /// computes differently is worse than no blurb.
    public static let blurb =
        "A real wingfoil session on Lake Garda — 31 flights, 50 jibes, 23.0 km and 56 % "
        + "foil time, with the track, the speed chart, the turn outcomes and the "
        + "heart-rate cost all filled in."

    /// The bundled FIT inside the kit's resource bundle.
    public static var url: URL? {
        Bundle.module.url(forResource: "ExampleSession", withExtension: "fit",
                          subdirectory: "Resources")
            // SwiftPM flattens single-file resources in some toolchain versions; the
            // fallback keeps the lookup working either way rather than silently
            // disabling the button.
            ?? Bundle.module.url(forResource: "ExampleSession", withExtension: "fit")
    }

    public enum Failure: Error, LocalizedError {
        case missingFromBundle

        public var errorDescription: String? {
            "The example session is missing from this build."
        }
    }

    /// The bundled FIT's bytes, ready for the normal import path.
    public static func data() throws -> Data {
        guard let url else { throw Failure.missingFromBundle }
        return try Data(contentsOf: url)
    }
}

extension SessionIngestor {

    /// Imports the bundled example through the ordinary ingest path — same parser, same
    /// analysis, same archive, same dedupe — tagged `.example` so the row is flagged.
    ///
    /// Dedupe interaction (documented in docs/testing.md): the example *is* a real
    /// recording, so a rider who later imports the same activity from intervals.icu or a
    /// Garmin export will hit the ±60 s dedupe key. That case resolves in favour of the
    /// real import — `note(…)` clears `isExample`, promoting the row into Records and
    /// Trends — rather than leaving the rider's own session permanently excluded.
    @discardableResult
    public func importExample() async throws -> IngestOutcome {
        try await ingest(fitData: ExampleSession.data(), filename: ExampleSession.filename,
                         source: .example)
    }
}
