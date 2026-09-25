import Foundation
import Testing
@testable import WingFoilKit

/// A flaky network on the beach is retried quietly; a revoked account or a rejected key is
/// said at once, inline, with its fix (`SyncTrouble`). These pin the classification, the
/// backoff and the moment a line first appears.
struct SyncTroubleTests {

    // MARK: - Classification

    @Test(arguments: [URLError.Code.notConnectedToInternet, .networkConnectionLost, .timedOut,
                      .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost,
                      .dataNotAllowed, .secureConnectionFailed])
    func networkFailuresAreTransient(_ code: URLError.Code) {
        #expect(SyncFailureKind.classify(URLError(code)) == .transient)
        // The same failure as a bare NSError, which is how some frameworks hand it over.
        let ns = NSError(domain: NSURLErrorDomain, code: code.rawValue)
        #expect(SyncFailureKind.classify(ns) == .transient)
    }

    @Test func aDroppedSocketIsTransient() {
        let reset = NSError(domain: NSPOSIXErrorDomain, code: 54)   // ECONNRESET
        #expect(SyncFailureKind.classify(reset) == .transient)
    }

    @Test func stravaErrorsSplitIntoRetryAndFix() {
        #expect(SyncFailureKind.classify(StravaClient.Error.transport("offline")) == .transient)
        #expect(SyncFailureKind.classify(StravaClient.Error.unauthorized) == .reconnect)
        #expect(SyncFailureKind.classify(StravaClient.Error.notConnected) == .reconnect)
        #expect(SyncFailureKind.classify(StravaClient.Error.athleteLimit) == .stravaFull)
        #expect(SyncFailureKind.classify(StravaClient.Error.rateLimited(retryAfterS: 120))
                == .rateLimited(retryAfterS: 120))
        #expect(SyncFailureKind.classify(StravaClient.Error.http(status: 503, body: ""))
                == .transient)
        #expect(SyncFailureKind.classify(StravaClient.Error.http(status: 401, body: ""))
                == .reconnect)
        #expect(SyncFailureKind.classify(StravaClient.Error.http(status: 429, body: ""))
                == .rateLimited(retryAfterS: nil))
        if case .other = SyncFailureKind.classify(StravaClient.Error.decoding("x")) {} else {
            Issue.record("a response we could not read is neither a blip nor a fix")
        }
    }

    @Test func intervalsErrorsSplitIntoRetryAndFix() {
        #expect(SyncFailureKind.classify(IcuClient.Error.transport("dns")) == .transient)
        #expect(SyncFailureKind.classify(IcuClient.Error.unauthorized) == .keyRejected)
        #expect(SyncFailureKind.classify(IcuClient.Error.missingKey) == .keyRejected)
        #expect(SyncFailureKind.classify(IcuClient.Error.http(status: 403, body: ""))
                == .keyRejected)
        #expect(SyncFailureKind.classify(IcuClient.Error.http(status: 502, body: ""))
                == .transient)
        #expect(SyncFailureKind.classify(IcuClient.Error.http(status: 404, body: ""))
                == .other(detail: "HTTP 404"))
    }

    @Test func anUnknownErrorIsOtherNeverTransient() {
        struct Odd: Error {}
        let kind = SyncFailureKind.classify(Odd())
        #expect(!kind.isRetryable)
        #expect(!kind.isActionable)
    }

    @Test func actionableIsTheFixKindsAndTheRateLimit() {
        #expect(SyncFailureKind.reconnect.isActionable)
        #expect(SyncFailureKind.keyRejected.isActionable)
        #expect(SyncFailureKind.stravaFull.isActionable)
        #expect(SyncFailureKind.rateLimited(retryAfterS: nil).isActionable)
        #expect(!SyncFailureKind.transient.isActionable)
    }

    // MARK: - Backoff

    @Test func transientBacksOffThenStops() {
        #expect(SyncRetryPolicy.delay(afterFailures: 1, kind: .transient) == 30)
        #expect(SyncRetryPolicy.delay(afterFailures: 2, kind: .transient) == 120)
        #expect(SyncRetryPolicy.delay(afterFailures: 3, kind: .transient) == 600)
        #expect(SyncRetryPolicy.delay(afterFailures: 4, kind: .transient) == nil)
    }

    @Test func aRateLimitWaitsForStravasOwnNumber() {
        #expect(SyncRetryPolicy.delay(afterFailures: 1, kind: .rateLimited(retryAfterS: 300))
                == 300)
        #expect(SyncRetryPolicy.delay(afterFailures: 1, kind: .rateLimited(retryAfterS: nil))
                == 30)
        // A day's cap is not waited out in-process: the next launch tries again.
        #expect(SyncRetryPolicy.delay(afterFailures: 1, kind: .rateLimited(retryAfterS: 86_400))
                == nil)
    }

    @Test func aFixIsNeverRetried() {
        for kind in [SyncFailureKind.reconnect, .keyRejected, .stravaFull, .other(detail: nil)] {
            #expect(SyncRetryPolicy.delay(afterFailures: 1, kind: kind) == nil)
        }
    }

    // MARK: - When a line appears

    @Test func aBlipIsSilentUntilTheThirdInARow() {
        var troubles = SyncTroubles()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        troubles.recordFailure(.transient, from: .strava, at: now, riderAsked: false)
        troubles.recordFailure(.transient, from: .strava, at: now, riderAsked: false)
        #expect(troubles.footerLines.isEmpty)
        let third = troubles.recordFailure(.transient, from: .strava, at: now, riderAsked: false)
        #expect(third.failures == 3)
        #expect(troubles.footerLines == ["Strava not reached · trying again later"])
        #expect(third.settingsLine == "Last try failed: no connection")
    }

    @Test func aSuccessClearsTheLine() {
        var troubles = SyncTroubles()
        let now = Date()
        for _ in 0..<3 {
            troubles.recordFailure(.transient, from: .intervals, at: now, riderAsked: false)
        }
        #expect(!troubles.footerLines.isEmpty)
        troubles.recordSuccess(from: .intervals)
        #expect(troubles.footerLines.isEmpty)
        #expect(troubles[.intervals] == nil)
    }

    @Test func aFixIsShownAtTheFirstFailure() {
        var troubles = SyncTroubles()
        troubles.recordFailure(.reconnect, from: .strava, at: Date(), riderAsked: false)
        #expect(troubles.footerLines == ["Strava needs you to connect again · Settings → Strava"])
    }

    @Test func whatTheRiderAskedForIsShownAtOnce() {
        var troubles = SyncTroubles()
        troubles.recordFailure(.transient, from: .intervals, at: Date(), riderAsked: true)
        #expect(troubles.footerLines == ["intervals.icu not reached · pull to try again"])
    }

    @Test func linesKeepAFixedOrder() {
        var troubles = SyncTroubles()
        let now = Date()
        troubles.recordFailure(.other(detail: nil), from: .watch, at: now, riderAsked: false)
        troubles.recordFailure(.keyRejected, from: .intervals, at: now, riderAsked: false)
        troubles.recordFailure(.reconnect, from: .strava, at: now, riderAsked: false)
        #expect(troubles.footerLines.count == 3)
        #expect(troubles.footerLines.first?.hasPrefix("Strava") == true)
        #expect(troubles.footerLines.last == "A session from your watch did not come in")
    }

    @Test func troublesSurviveARelaunch() throws {
        var troubles = SyncTroubles()
        troubles.recordFailure(.rateLimited(retryAfterS: 60), from: .strava,
                               at: Date(timeIntervalSince1970: 1_800_000_000), riderAsked: false)
        let data = try JSONEncoder().encode(troubles)
        #expect(try JSONDecoder().decode(SyncTroubles.self, from: data) == troubles)
    }

    @Test func onlyTheDoorsThatRunByThemselvesHaveASource() {
        #expect(SyncSource(importSource: .appleHealth) == .health)
        #expect(SyncSource(importSource: .appleWatch) == .watch)
        #expect(SyncSource(importSource: .file) == nil)
        #expect(SyncSource(importSource: .gdpr) == nil)
    }
}
