import Foundation

/// **The divergence banner's words, built from the document's numbers.**
///
/// `Divergence` carried four pre-formatted strings until round 2 of ADR-033 — the metric's
/// name, both values and the delta — which is why the presentation document could not carry
/// the banner at all: a formatted number in the document breaks its second rule and a
/// rider sentence breaks its first. The check emits raw values and ids now, and this is the
/// renderer, in the kit because the Log tab's table and the banner over the block are two
/// surfaces printing one line.
///
/// The unit is deliberately read at print time (`Speed`): a rider who switches to km/h gets
/// both numbers in km/h, and the *dismissal* he made yesterday still holds, because the
/// fingerprint is over the raw values now rather than over the strings they were shown as.
public enum DivergenceText {

    /// "Foil time", "Best 2 s" — the metric's name, from the id the line carries.
    public static func metric(_ line: Divergence) -> String {
        PresentationCopy.text(line.labelId) ?? line.metricId
    }

    /// What the watch wrote, in the rider's unit.
    public static func watch(_ line: Divergence) -> String {
        value(line.watchValue, unitKind: line.unitKind)
    }

    /// What the phone recomputed, in the rider's unit.
    public static func phone(_ line: Divergence) -> String {
        value(line.phoneValue, unitKind: line.unitKind)
    }

    /// The signed difference, **in the unit the difference is interesting in**: a percentage
    /// for foil time (five minutes on an hour is not five minutes on four), the rider's
    /// speed unit for a record, a plain signed integer for a count.
    public static func delta(_ line: Divergence) -> String {
        let change = line.phoneValue - line.watchValue
        switch line.unitKind {
        case "durationS":
            guard line.watchValue > 0 else { return "—" }
            return String(format: "%+.0f %%", change / line.watchValue * 100)
        case "speedKn":
            return String(format: "%+.2f %@", Speed.value(change), Speed.suffix)
        default:
            return String(format: "%+d", Int(change.rounded()))
        }
    }

    /// One value in its unit. Foil time is `m:ss` on the session clock — the banner's own
    /// spelling, kept because it is a *duration measured by two devices*, which is what the
    /// table is comparing, rather than the session clock the block prints.
    static func value(_ raw: Double, unitKind: String) -> String {
        switch unitKind {
        case "durationS":
            let total = Int(raw.rounded())
            return String(format: "%d:%02d", total / 60, total % 60)
        case "speedKn":
            return Speed.format(raw)
        default:
            return String(Int(raw.rounded()))
        }
    }

    /// **The banner's one line.** "Watch and phone disagree on foil time and best 2 s", or
    /// "… on foil time, flights and 3 more" past two.
    ///
    /// Lowercased at the point of printing rather than in the copy: the same words are a
    /// column heading in the Log tab's table, where they are capitalised, and a metric with
    /// two spellings is the defect the glossary exists to stop.
    public static func banner(_ lines: [Divergence]) -> String {
        PresentationCopy.text("presentation.banner.divergence",
                              args: ["metrics": list(lines)]) ?? ""
    }

    /// How the list of names ends — the renderer's decision, from the two shapes copy holds.
    static func list(_ lines: [Divergence]) -> String {
        let names = lines.map { metric($0).lowercased() }
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2:
            return PresentationCopy.text("presentation.banner.divergencePair",
                                         args: ["first": names[0], "second": names[1]]) ?? ""
        default:
            return PresentationCopy.text(
                "presentation.banner.divergenceMore",
                args: ["first": names.prefix(2).joined(separator: ", "),
                       "rest": String(names.count - 2)]) ?? ""
        }
    }

    /// **The takeoff-only case.** Both takeoff counts come off the same accelerometer
    /// channel the watch and the phone read differently by design, so a table that carries
    /// nothing else says so rather than looking like a fault.
    public static func isTakeoffOnly(_ lines: [Divergence]) -> Bool {
        !lines.isEmpty && lines.allSatisfy {
            $0.metricId == "takeoffs" || $0.metricId == "takeoffAttempts"
        }
    }
}
