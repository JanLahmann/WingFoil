import Foundation

/// The four recording classes, **named**, in the words docs/channels.md settled on.
///
/// **Why they have names at all now.** The engine has always had the letters — `SessionRow
/// .sourceClass` is `"a"`, `"b"` or `"c"`, the fixtures and the goldens speak them, and the
/// help catalogue was deliberately de-jargoned so that no rider ever read "class b" on a
/// screen. That was right while the letters were the *whole* of what a rider would have been
/// told, because a letter in somebody else's taxonomy answers nothing. It stopped being right
/// on 14 September 2026, when the question moved *in front of* the import: cleanjibe.org and
/// cleanjibe.org/watches print the table as "what you need, what you get", and a rider who has
/// read it there arrives at Import looking for the row he read. A name he can match beats a
/// silence he has to re-derive.
///
/// So the letter is never alone. Every name is **the letter and the thing**, in that order —
/// "Class A · Garmin watch app" — which reads as a label to somebody who has seen the table
/// and as a plain description to somebody who has not.
///
/// **One wording, three surfaces.** These strings are the same ones in `web/index.html` and
/// `web/watches/index.html` (the leading cell of each row) and in docs/channels.md's table.
/// The iOS Import footers and the help topic "What your recording can and cannot show" read
/// them from here rather than retyping them, because a class that is called one thing on the
/// website and another in the app is a class the rider will not connect.
public enum RecordingClass: String, Sendable, CaseIterable, Identifiable {
    /// The CleanJibe watch app on a Garmin: everything, including the wrist.
    case a
    /// Any other file that carries the receiver's own speed.
    case b
    /// The CleanJibe Apple Watch app: class b speed plus the 50 Hz wrist accelerometer
    /// (ADR-016), analysed on the phone. Not a fourth letter in the engine — a class b
    /// recording with an accelerometer stream beside it — which is why it is written as a
    /// `+` rather than as a `d`.
    case bPlus
    /// Positions only: Strava, a GPX, a TCX with no speed channel, a phone in a pouch.
    case c

    public var id: String { rawValue }

    /// "Class A · Garmin watch app" — the letter and the thing, in that order.
    public var name: String {
        switch self {
        case .a: "Class A · Garmin watch app"
        case .b: "Class B · any speed-certified file"
        case .bPlus: "Class B+ · Apple Watch app"
        case .c: "Class C · positions only"
        }
    }

    /// One line on what the class gets you, phrased as an answer to *what do I lose* rather
    /// than as a feature list — which is the question a rider asks at the moment he is
    /// choosing a door.
    public var line: String {
        switch self {
        case .a:
            "Everything. Foil time, flights, every turn verdict and clean jibe, certified "
            + "speed records, the wind axis. Pump strokes and takeoff attempts too."
        case .b:
            "Everything except pump strokes and takeoff attempts, which need a wrist "
            + "accelerometer nothing else records. Speed records certify."
        case .bPlus:
            "Everything class B gets, plus pump strokes and takeoff attempts. The watch app "
            + "records the wrist at 50 Hz. The phone analyses it."
        case .c:
            "Foil time, flights, every turn verdict and clean jibe, the wind axis. Speed "
            + "records are estimated from positions and marked uncertified, and there are "
            + "no pump strokes or takeoff attempts."
        }
    }

    /// "Class A · Garmin watch app: everything: …" — the two halves as one paragraph, which
    /// is the shape a section footer wants.
    public var footerLine: String { name + ". " + line }
}
