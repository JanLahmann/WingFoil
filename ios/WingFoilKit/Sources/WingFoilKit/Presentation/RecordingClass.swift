import Foundation

/// The four recording classes, **named by what the rider gets**.
///
/// **The letters stay in the code and nowhere else.** The engine has always had them —
/// `SessionRow.sourceClass` is `"a"`, `"b"` or `"c"`, and the fixtures and the goldens speak
/// them. From 14 September 2026 the screens printed them too, as "the letter and the thing"
/// ("Class B · any file with measured speed"), so a rider could match the table on
/// cleanjibe.org to the Import screen. The rider review of 9 October 2026 asked the question
/// that settled it: *"What is Class A or Class B?"* A letter in somebody else's taxonomy
/// answers nothing, and the thing beside it already said all of it. So the name is now
/// **only the thing, said as what you get** — "Measured speed", "Positions only" — the same
/// words the web's session badge and the Import footers use.
///
/// **One wording, three surfaces.** These strings are the lead cells of the table on
/// cleanjibe.org/start#watches, the route pills on /start/, and the Import screen's label
/// above each door's footer (`ImportDoor.classLabel`). A thing that is called one way on the
/// website and another in the app is a thing the rider will not connect.
public enum RecordingClass: String, Sendable, CaseIterable, Identifiable {
    /// The CleanJibe watch app on a Garmin: everything, including the wrist.
    case a
    /// Any other file that carries the receiver's own speed.
    case b
    /// The CleanJibe Apple Watch app: measured speed plus the 50 Hz wrist accelerometer
    /// (ADR-016), analysed on the phone. Not a fourth letter in the engine — a class b
    /// recording with an accelerometer stream beside it — which is why it is written as a
    /// `+` rather than as a `d`.
    case bPlus
    /// Positions only: Strava, a GPX, a TCX with no speed channel, a phone in a pouch.
    case c

    public var id: String { rawValue }

    /// What the rider gets, as a label: "Measured speed", "Positions only". No letter.
    public var name: String {
        switch self {
        case .a: "Everything"
        case .b: "Measured speed"
        case .bPlus: "Measured speed and the wrist"
        case .c: "Positions only"
        }
    }

    /// One line on what the class gets you, phrased as an answer to *what do I lose* rather
    /// than as a feature list — which is the question a rider asks at the moment he is
    /// choosing a door.
    public var line: String {
        switch self {
        case .a:
            "Foil time, flights, every turn verdict and clean jibe, measured speed records, "
            + "the wind axis. Pump strokes and takeoff attempts too."
        case .b:
            "Everything except pump strokes and takeoff attempts, which need a wrist "
            + "accelerometer nothing else records."
        case .bPlus:
            "Everything a file with measured speed gets, plus pump strokes and takeoff "
            + "attempts. The watch app records the wrist at 50 Hz. The phone analyses it."
        case .c:
            "Foil time, flights, every turn verdict and clean jibe, the wind axis. Speed "
            + "records are estimated from positions and marked so, and there are "
            + "no pump strokes or takeoff attempts."
        }
    }

    /// "Measured speed. Everything except …" — the two halves as one paragraph, which
    /// is the shape a section footer wants.
    public var footerLine: String { name + ". " + line }
}
