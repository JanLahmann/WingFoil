import Foundation

/// The phone half of the companion link, as an interface.
///
/// WHY THIS PROTOCOL EXISTS AT ALL. The real implementation is
/// `ConnectIQCompanionLink` in the app target, and it needs Garmin's `ConnectIQ`
/// xcframework — a binary, ObjC, iOS-only dependency that cannot be linked into a package
/// test run and would not build on a machine that has never seen a watch. **WingFoilKit
/// must never import ConnectIQ.** Keeping the seam here means the payload contract, the
/// reconciliation and every rule about what a card may contain stay unit-testable with no
/// framework, no Garmin Connect Mobile, and no hardware in the room — which is exactly the
/// part of this feature that can actually be wrong.
///
/// Everything is `async` because the concrete adapter owns BLE state that arrives on
/// Garmin's own delegate queue, so it is an actor; a synchronous requirement here would
/// force it not to be one.
public protocol CompanionLink: Sendable {

    /// What the UI is allowed to promise the rider right now.
    var state: CompanionLinkState { get async }

    /// The manual "send wind to watch" action. `degreesFrom` is the direction the wind
    /// blows FROM, 0…359, or -1 to clear it — the same encoding the watch's own wind menu
    /// uses, so the push lands in exactly the setting the on-water turn classifier reads.
    ///
    /// Manual, not automatic, by decision: an automatic push needs the app awake at the
    /// moment a session starts, and a wind axis that arrives half a session late relabels
    /// every tack as a jibe. Automatic can come later, once the link is proven on water.
    func sendWind(degreesFrom: Int) async throws

    /// Cards pushed by the watch, in arrival order, already decoded and validated.
    ///
    /// A stream rather than a delegate: the consumer is `SessionStore`, which wants to
    /// ingest each card and refresh the library, and a `for await` loop in one `Task` is
    /// the whole of that. Cards that fail validation never reach here.
    func summaries() async -> AsyncStream<CompanionSummary>
}

/// How far the link got. Ordered from "nothing we can do" to "the watch is listening";
/// the UI shows the reason verbatim, because every one of these is fixable by the rider
/// and none of them is fixable by us.
public enum CompanionLinkState: Sendable, Equatable {
    /// Garmin Connect Mobile is not installed, so there is no path to the watch at all.
    case noConnectMobile
    /// GCM is there, but the rider has not handed us a device yet.
    case noDevice
    /// A device is known but not currently connected (watch off, out of range, in a car).
    case deviceOffline(name: String)
    /// Connected, but our CIQ app did not answer a status check: either it is not
    /// installed on this watch, or it is installed and not currently open. The link
    /// cannot tell those apart, and neither ends with a message arriving.
    case appNotRunning(name: String)
    /// The watch app is reachable; a wind push will arrive.
    case ready(name: String)

    public var canSend: Bool {
        if case .ready = self { return true }
        return false
    }

    /// The connected device's name, when there is one to show.
    public var deviceName: String? {
        switch self {
        case .noConnectMobile, .noDevice: nil
        case .deviceOffline(let name), .appNotRunning(let name), .ready(let name): name
        }
    }
}

extension CompanionLinkState {

    /// One line for the settings row. Every one of these is the rider's to fix, so each
    /// says what is missing rather than that something failed.
    public var headline: String {
        switch self {
        case .noConnectMobile: "Garmin Connect not installed"
        case .noDevice: "No watch chosen"
        case .deviceOffline(let name): "\(name) — not connected"
        case .appNotRunning(let name): "\(name) — WingFoil app not running"
        case .ready(let name): "\(name) — ready"
        }
    }

    public var detail: String {
        switch self {
        case .noConnectMobile:
            "The link goes through the Garmin Connect app, which owns the Bluetooth "
            + "connection to your watch. Install it and pair your watch there first."
        case .noDevice:
            "Choose your watch in Garmin Connect. WingFoil only ever talks to the watch "
            + "you pick here."
        case .deviceOffline:
            "Sessions still reach the library through the FIT file — the watch link only "
            + "makes them arrive sooner. Bring the watch into range to send wind to it."
        case .appNotRunning:
            "Open the WingFoil app on the watch: it only listens while it is running. "
            + "Session summaries are sent when you save, whether this app is open or not."
        case .ready:
            "Your watch sends a session summary the moment you save, and accepts a wind "
            + "direction from here."
        }
    }
}

public enum CompanionLinkError: Error, Equatable, Sendable {
    /// Nothing to send to — see `CompanionLinkState` for which stage failed.
    case notReady(CompanionLinkState)
    /// Outside 0…359 and not the -1 that clears it. Rejected here rather than on the
    /// watch, so a bad value never costs a BLE round trip.
    case invalidWind(Int)
    /// The radio accepted the message and then failed; the string is Garmin's own.
    case transmitFailed(String)

    /// What to put on screen. Garmin's own failure word is kept verbatim in the transmit
    /// case: it is the only thing that distinguishes "watch busy" from "app not there",
    /// and paraphrasing it would cost the one detail worth having.
    public var riderMessage: String {
        switch self {
        case .notReady(let state): state.headline
        case .invalidWind(let degrees): "\(degrees)° is not a wind direction."
        case .transmitFailed(let reason): "The watch did not take it (\(reason))."
        }
    }
}

/// Wind values the link will carry: a bearing, or -1 meaning "forget the one you have".
public enum CompanionWind {
    public static let clear = -1

    public static func isValid(_ degreesFrom: Int) -> Bool {
        degreesFrom == clear || (0...359).contains(degreesFrom)
    }
}

// MARK: - Test double

/// An in-memory `CompanionLink`: no radio, no framework, no watch.
///
/// It exists so the reconciliation tests and the UI can be driven end to end on a machine
/// with none of those things. It records what was sent and lets a test push cards in at
/// the moment of its choosing, which is the one thing the real link can never be made to
/// do on demand.
public actor FakeCompanionLink: CompanionLink {

    public private(set) var state: CompanionLinkState
    /// Every wind value handed to `sendWind`, in order — including ones a test made fail.
    public private(set) var sentWind: [Int] = []
    /// Set to make the next sends fail, the way a watch going out of range does.
    public var nextSendError: CompanionLinkError?

    private let stream: AsyncStream<CompanionSummary>
    private let continuation: AsyncStream<CompanionSummary>.Continuation

    public init(state: CompanionLinkState = .ready(name: "fenix 8")) {
        self.state = state
        // Unbounded, so a card pushed before anyone iterates is still waiting when the
        // consumer arrives — a test should not have to win a race to observe a delivery.
        let (stream, continuation) = AsyncStream<CompanionSummary>.makeStream(
            bufferingPolicy: .unbounded)
        self.stream = stream
        self.continuation = continuation
    }

    public func summaries() -> AsyncStream<CompanionSummary> { stream }

    public func sendWind(degreesFrom: Int) throws {
        guard CompanionWind.isValid(degreesFrom) else {
            throw CompanionLinkError.invalidWind(degreesFrom)
        }
        sentWind.append(degreesFrom)
        if let error = nextSendError { throw error }
        guard state.canSend else { throw CompanionLinkError.notReady(state) }
    }

    // MARK: Test control

    public func set(state: CompanionLinkState) { self.state = state }

    public func set(nextSendError: CompanionLinkError?) { self.nextSendError = nextSendError }

    /// Pretends the watch just transmitted a card.
    public func deliver(_ summary: CompanionSummary) { continuation.yield(summary) }

    /// Ends the stream, so a `for await` consumer finishes instead of hanging a test.
    public func finish() { continuation.finish() }
}
