import Foundation
import Testing
import WingFoilKit
@testable import WingFoil

/// **A session is never called by its identifier.**
///
/// The Apple Watch app filed its containers under the recording's UUID until 0.9.13, and a
/// tester read "EE94C0B1 359A 4FED …" off his own library where the afternoon's name
/// belonged. The writer names the files properly now and `SessionNaming.derivedTitle`
/// catches the ones already on a phone — this is the app's side of that rule, on the
/// function every one of the eleven surfaces actually calls.
@Suite struct SessionTitleTests {

    /// `8-4-4-4-12` hexadecimal, spelled out here rather than borrowed from the kit: the
    /// rule this suite is checking is the one that must not be able to change silently on
    /// both sides at once.
    private func isBareIdentifier(_ text: String) -> Bool {
        text.wholeMatch(of: /[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}/) != nil
    }

    private func row(filename: String?, custom: String? = nil) -> SessionRow {
        var row = SessionRow(id: "EE94C0B1-359A-4FED-9A1E-1234567890AB",
                             startDate: Date(timeIntervalSince1970: 1_756_540_000),
                             durationS: 3600, sourceClass: "b")
        row.originalFilename = filename
        row.customTitle = custom
        return row
    }

    @Test(arguments: [
        "EE94C0B1-359A-4FED-9A1E-1234567890AB.fit",
        "EE94C0B1-359A-4FED-9A1E-1234567890AB",
        "2026-08-30-1440_EE94C0B1-359A-4FED-9A1E-1234567890AB_applewatch.fit",
        "ee94c0b1-359a-4fed-9a1e-1234567890ab.cjw",
    ])
    func aRecordingNamedAfterItsIdentifierGetsARealName(_ filename: String) {
        let title = SessionDisplay.title(row(filename: filename))
        #expect(!isBareIdentifier(title))
        #expect(title == SessionNaming.sport)
    }

    /// The rest of the rule, so the first half cannot be satisfied by calling everything
    /// "Wingfoil": a real filename still becomes the name it always was.
    @Test func aRealFilenameStillBecomesItsOwnName() {
        #expect(SessionDisplay.title(
            row(filename: "2026-08-03-1440_nago-torbole-windsurfen_native.fit"))
                == "Nago Torbole Wingfoil")
        #expect(SessionDisplay.title(
            row(filename: "14123456789_Wingfoil-am-Nachmittag_strava.gpx"))
                == "Wingfoil am Nachmittag")
    }

    /// A row with no recording behind it — the watch's BLE card before its FIT lands — has
    /// no filename to derive from, and must not fall back to the row id either.
    @Test func aRowWithNoRecordingIsStillNotCalledById() {
        let title = SessionDisplay.title(row(filename: nil))
        #expect(!isBareIdentifier(title))
        #expect(!title.isEmpty)
    }

    /// And the rider's own name wins over every derivation, which is the whole reason the
    /// eleven surfaces call this one function.
    @Test func theRidersOwnNameWins() {
        #expect(SessionDisplay.title(row(filename: "whatever_the-spot_native.fit",
                                         custom: "First 20 kn"))
                == "First 20 kn")
    }
}
