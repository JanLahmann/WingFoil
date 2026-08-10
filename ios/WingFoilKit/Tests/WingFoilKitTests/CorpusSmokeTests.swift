import Foundation
import Testing
@testable import WingFoilKit

/// Full-pipeline smoke over every fixture FIT (12 real sessions + synthetic):
/// parse → clean → segment → records must run without error and produce physically
/// sane numbers. Prints a per-session table for eyeballing against on-water feel.
@Suite struct CorpusSmokeTests {

    @Test func corpusAnalyzesSanely() throws {
        let fits = allFixtureFITs()
        guard !fits.isEmpty else {
            print("CorpusSmokeTests: no fixture FITs found — nothing to smoke.")
            return
        }

        var rows: [String] = []
        for url in fits {
            let name = url.lastPathComponent
            let raw = try FitSessionParser.parse(url: url)
            let a = SessionSummarizer.analyze(raw)
            let r = a.records
            let s = a.summary

            #expect(s.foilPct >= 0 && s.foilPct <= 100, "\(name): foilPct \(s.foilPct)")
            if let b2 = r.best2sKn, let b10 = r.best10sKn {
                #expect(b2 >= b10 - 1e-9, "\(name): best2s \(b2) < best10s \(b10)")
            }
            if let b10 = r.best10sKn, let b5 = r.best5x10sKn {
                #expect(b10 >= b5 - 1e-9, "\(name): best10s \(b10) < best5x10s \(b5)")
            }
            let speeds: [(String, Double?)] = [
                ("best2s", r.best2sKn), ("best10s", r.best10sKn), ("best5x10s", r.best5x10sKn),
                ("best100m", r.best100mKn), ("best250m", r.best250mKn), ("best500m", r.best500mKn),
                ("bestNm", r.bestNmKn), ("bestHour", r.bestHourKn), ("alpha500", r.alpha500Kn),
            ]
            for (key, value) in speeds {
                if let v = value {
                    #expect(v >= 0 && v < 45, "\(name): \(key) \(v) kn out of range")
                }
            }
            for (i, f) in a.flights.enumerated() {
                #expect(f.maxKn < 45, "\(name): flight[\(i)].maxKn \(f.maxKn)")
                #expect(f.endTs > f.startTs, "\(name): flight[\(i)] non-positive duration")
            }

            rows.append(row(name: name, rateHz: raw.capabilities.sampleRateHz,
                            analysis: a))
        }

        let header = pad("session", 52) + pad("Hz", 5) + pad("foil%", 7) + pad("flts", 6)
            + pad("2s kn", 8) + pad("500m kn", 9) + pad("alpha", 8) + pad("km", 7)
        print(header)
        print(String(repeating: "-", count: header.count))
        rows.forEach { print($0) }
    }

    private func row(name: String, rateHz: Double, analysis a: SessionAnalysis) -> String {
        pad(String(name.prefix(50)), 52)
            + pad(fmt(rateHz, 1), 5)
            + pad(fmt(a.summary.foilPct, 1), 7)
            + pad("\(a.summary.flightCount)", 6)
            + pad(a.records.best2sKn.map { fmt($0, 2) } ?? "-", 8)
            + pad(a.records.best500mKn.map { fmt($0, 2) } ?? "-", 9)
            + pad(a.records.alpha500Kn.map { fmt($0, 2) } ?? "-", 8)
            + pad(fmt(a.summary.distanceKm, 1), 7)
    }

    private func fmt(_ v: Double, _ places: Int) -> String {
        String(format: "%.\(places)f", v)
    }

    private func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s + " " : s + String(repeating: " ", count: width - s.count)
    }
}
