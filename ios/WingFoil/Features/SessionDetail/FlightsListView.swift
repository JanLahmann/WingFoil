import SwiftUI
import WingFoilKit

/// **Every flight, one row each: when it took off, how long it lasted, how it ended.**
///
/// A flight is a takeoff and an end, and until 25 September 2026 the two halves lived two
/// tabs apart — the takeoffs on their own tab, the straight-line ends on Details — while the
/// Ride tab printed "Flights · 23 detected", a count with nothing to open (Jan, F8k / F12c).
/// This is the list the count was standing in for, on the tab that is now called Flights.
///
/// The row is `FlightPairing.Flight`, the same pairing the map's flight popover and the
/// replay caption read, so a flight is numbered and timed one way everywhere. A row whose end
/// is a *drawn* flight end — a straight-line end no turn owns — opens that end's page, the
/// same one the hollow ring on the map opens. An end inside a turn says which turn, and the
/// turn's own page is on Turns.
struct FlightsListView: View {
    let detail: SessionDetail

    @State private var opened: FlightEndDetailRequest?
    @State private var showAll = false

    /// Past this many, the list folds: a sixty-flight afternoon is sixty rows, and the
    /// attempts underneath should not be three screens down.
    private static let folded = 8

    private var words: DisciplineLexicon { detail.row.analysisDiscipline.lexicon }

    private var flights: [FlightPairing.Flight] { FlightPairing.flights(detail.analysis) }

    /// flight index → its end's index in `analysis.flightEnds`.
    private var endIndex: [Int: Int] {
        var out: [Int: Int] = [:]
        for (index, end) in detail.analysis.flightEnds.enumerated()
            where out[end.flightIndex] == nil {
            out[end.flightIndex] = index
        }
        return out
    }

    var body: some View {
        let all = flights
        if !all.isEmpty {
            let drawn = Set(detail.drawnFlightEndIndices)
            let ends = endIndex
            let shown = showAll ? all : Array(all.prefix(Self.folded))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(words.flights).font(.headline)
                    HelpButton(topic: .flights, size: .footnote)
                    Spacer()
                    Text("\(all.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    headerRow
                    Divider()
                    ForEach(shown, id: \.index) { flight in
                        let end = ends[flight.index]
                        row(flight, end: end, opens: end.map(drawn.contains) ?? false)
                        Divider()
                    }
                    if all.count > Self.folded {
                        Button(showAll ? "Show fewer"
                                       : "Show all " + String(all.count) + " "
                                         + words.flights.lowercased()) {
                            withAnimation(.snappy) { showAll.toggle() }
                        }
                        .font(.footnote)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                    }
                }
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
                .denseRowTypeSizeCap()
            }
            .id("flights")
            .sheet(item: $opened) { request in
                FlightEndDetailSheet(detail: detail, start: request.id)
            }
            #if DEBUG && targetEnvironment(simulator)
            // `UI_OPEN_FLIGHT_END=<index>` opens one flight end's page, for a picture of it.
            // The same family as `UI_OPEN_TURN`, and the same index: into `flightEnds`.
            .onAppear {
                guard let raw = ProcessInfo.processInfo.environment["UI_OPEN_FLIGHT_END"],
                      let id = Int(raw),
                      detail.analysis.flightEnds.indices.contains(id) else { return }
                opened = FlightEndDetailRequest(id: id)
            }
            #endif
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text("up at").scaledColumn(46, relativeTo: .caption)
            Text("flight").frame(maxWidth: .infinity, alignment: .leading)
            Text("ended").scaledColumn(96, relativeTo: .caption)
        }
        .font(.caption2)
        .foregroundStyle(.readableSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func row(_ flight: FlightPairing.Flight, end: Int?, opens: Bool) -> some View {
        Button {
            if opens, let end { opened = FlightEndDetailRequest(id: end) }
        } label: {
            HStack(spacing: 10) {
                Text(Fmt.clock(flight.startTs))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .scaledColumn(46, relativeTo: .caption)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Flight " + String(flight.number) + " · "
                         + FlightPairing.clock(flight.durationS))
                        .font(.subheadline.monospacedDigit())
                    Text(takeoffLine(flight))
                        .font(.caption2)
                        .foregroundStyle(.readableSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    Image(systemName: flight.outcome.symbolName)
                        .font(.caption)
                        .foregroundStyle(FlightEndMark.color(flight.outcome))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(flight.outcome.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let turn = owningTurn(end) {
                            Text(turn)
                                .font(.caption2)
                                .foregroundStyle(.readableSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if opens {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .scaledColumn(96, relativeTo: .caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!opens)
        .accessibilityElement(children: .combine)
        .accessibilityHint(opens ? "Opens how this flight ended" : "")
    }

    /// How the flight got up: the strokes it took, "free" when it took none, and nothing
    /// at all where the recording has no pump channel — absent, never a zero.
    private func takeoffLine(_ flight: FlightPairing.Flight) -> String {
        var parts: [String] = []
        if words.pumping, let pumps = flight.pumps {
            parts.append(pumps == 0 ? "free takeoff"
                                    : String(pumps) + (pumps == 1 ? " pump" : " pumps"))
        }
        if let distM = flight.distM { parts.append(FlightPairing.metres(distM)) }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }

    /// "in jibe 3" — the turn an end inside a turn's window belongs to. Its page is the
    /// turn's, on Turns; this row only says where to find it.
    private func owningTurn(_ end: Int?) -> String? {
        guard let end, detail.analysis.flightEnds.indices.contains(end),
              let turn = detail.analysis.flightEnds[end].ownedByTurn,
              detail.analysis.turns.indices.contains(turn) else { return nil }
        return "in a " + TurnAnalytics.typeLabel(detail.analysis.turns[turn].type).lowercased()
    }
}

/// The ink a flight's end wears: the ladder's for a touchdown and a fall, the body's for a
/// glide-out and a recording that stopped (`FlightPairing.Outcome.colourRole`).
enum FlightEndMark {
    static func color(_ outcome: FlightPairing.Outcome) -> Color {
        switch outcome.colourRole {
        case "outcome.touchdown": DesignTokens.Outcome.touchdown
        case "outcome.fellIn": DesignTokens.Outcome.fellIn
        default: .secondary
        }
    }
}
