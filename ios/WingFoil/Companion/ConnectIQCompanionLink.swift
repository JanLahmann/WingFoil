import ConnectIQ
import Foundation
import UIKit
import WingFoilKit

/// The real `CompanionLink`: Garmin's ConnectIQ SDK, wrapped so that nothing above it has
/// to know the SDK exists.
///
/// WHY THIS FILE IS IN THE APP TARGET AND NOT IN WingFoilKit. `ConnectIQ` is a binary
/// Objective-C xcframework. A package that imports it cannot be built or tested without
/// it, and `swift test` on the kit would stop working on any machine that has never seen a
/// watch. So the kit declares the protocol and this file is the only place in the codebase
/// that says `import ConnectIQ` — everything interesting (what a card may contain, how a
/// card reconciles with its FIT) is tested over there, with no framework and no hardware.
///
/// WHY IT IS `@MainActor`. The SDK is a 2014-vintage ObjC singleton with delegate
/// callbacks and no documented queue guarantee. Rather than guess, every delegate method
/// here is `nonisolated`, extracts the few Sendable values it needs on whatever thread it
/// was called on, and hops to the main actor to touch state. The volume is a handful of
/// events per session; correctness is worth more than the hop.
///
/// WHAT IT CANNOT DO ON ITS OWN. Everything here goes through Garmin Connect Mobile: GCM
/// owns the BLE link to the watch and there is no way round it. No GCM, no watch chosen in
/// GCM, or GCM logged out, and this object is a well-behaved no-op that says why.
@MainActor
final class ConnectIQCompanionLink: NSObject, CompanionLink {

    /// Our CIQ app's UUID — the `id` attribute of `garmin/manifest.xml`. The watch app and
    /// this constant are the same identity; change one and the link goes quiet with no
    /// error anywhere, because the SDK simply routes messages to an app nobody is running.
    static let appUUID = UUID(uuidString: "b1ef484c-77b9-4a69-b33d-18574f3bcbde")!

    /// Must match `CFBundleURLSchemes` in project.yml. GCM reopens us on this scheme with
    /// the rider's device choice in the URL.
    static let urlScheme = "wingfoil-ciq"

    /// Garmin Connect Mobile's own scheme, declared in `LSApplicationQueriesSchemes` —
    /// `canOpenURL` lies (returns false) for any scheme that is not declared there.
    private static let gcmScheme = "gcm-ciq"

    private(set) var state: CompanionLinkState = .noDevice

    private var device: IQDevice?
    private var app: IQApp?
    private let continuation: AsyncStream<CompanionSummary>.Continuation
    private let stream: AsyncStream<CompanionSummary>

    /// Cards that failed validation, counted rather than surfaced. A dropped card is
    /// invisible to the rider by design — the FIT is still coming — but a number that only
    /// ever goes up is the first thing to look at when the link "does not work".
    private(set) var rejectedCards = 0

    override init() {
        let (stream, continuation) = AsyncStream<CompanionSummary>.makeStream(
            bufferingPolicy: .unbounded)
        self.stream = stream
        self.continuation = continuation
        super.init()

        ConnectIQ.sharedInstance().initialize(withUrlScheme: Self.urlScheme,
                                              uiOverrideDelegate: self)
        // A watch the rider already chose survives a relaunch: IQDevice is reconstructable
        // from three strings, so the whole "go to GCM and pick a watch" dance happens once.
        if let stored = StoredDevice.load() { adopt(stored.device) }
        refresh()
    }

    // MARK: - CompanionLink

    func summaries() -> AsyncStream<CompanionSummary> { stream }

    func sendWind(degreesFrom: Int) async throws {
        guard CompanionWind.isValid(degreesFrom) else {
            throw CompanionLinkError.invalidWind(degreesFrom)
        }
        refresh()
        guard let app, state.canSend else { throw CompanionLinkError.notReady(state) }

        // The wire format is the watch's `PhoneLink.KEY_IN_WIND`: one key, one integer,
        // and the watch refuses anything else (a Float there would silently relabel every
        // tack as a jibe for the rest of the session).
        let message: [String: Any] = ["wd": degreesFrom]
        let result: IQSendMessageResult = await withCheckedContinuation { continuation in
            ConnectIQ.sharedInstance().sendMessage(message, to: app, progress: nil) { result in
                continuation.resume(returning: result)
            }
        }
        guard result == .success else {
            throw CompanionLinkError.transmitFailed(NSStringFromSendMessageResult(result))
        }
    }

    // MARK: - Device selection

    /// Whether there is any path to a watch at all. False means GCM is not installed, and
    /// no amount of tapping in this app will change that.
    var connectMobileInstalled: Bool {
        guard let url = URL(string: "\(Self.gcmScheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Hands over to Garmin Connect Mobile, which owns the list of the rider's watches.
    /// GCM comes back through `handle(url:)`.
    func chooseDevice() {
        ConnectIQ.sharedInstance().showDeviceSelection()
    }

    /// The return leg from GCM. Returns false for a URL that is not ours, so the app
    /// entry point can go on treating it as a shared FIT.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.scheme == Self.urlScheme else { return false }
        let devices = ConnectIQ.sharedInstance().parseDeviceSelectionResponse(from: url)
        // The rider may share several watches; we talk to one. First is the one GCM
        // considers primary, and picking silently beats a modal nobody asked for.
        guard let device = devices?.first as? IQDevice else {
            state = .noDevice
            return true
        }
        StoredDevice(device: device).save()
        adopt(device)
        refresh()
        return true
    }

    /// Forget the watch — the only way back out of a wrong choice.
    func forgetDevice() {
        if let device { ConnectIQ.sharedInstance().unregister(forDeviceEvents: device, delegate: self) }
        if let app { ConnectIQ.sharedInstance().unregister(forAppMessages: app, delegate: self) }
        device = nil
        app = nil
        StoredDevice.clear()
        state = .noDevice
    }

    private func adopt(_ device: IQDevice) {
        self.device = device
        let app = IQApp(uuid: Self.appUUID, store: nil, device: device)
        self.app = app
        ConnectIQ.sharedInstance().register(forDeviceEvents: device, delegate: self)
        // Registered unconditionally, not only when the watch is connected: the card
        // arrives on this callback the moment the rider is back in Bluetooth range, and
        // registering "once we are ready" would miss exactly that edge.
        if let app { ConnectIQ.sharedInstance().register(forAppMessages: app, delegate: self) }
    }

    // MARK: - State

    /// Re-reads what the SDK thinks the link can do. Cheap and synchronous; called before
    /// every send and whenever a screen appears, because the answer changes when the rider
    /// walks away from the watch and nothing tells us.
    func refresh() {
        guard connectMobileInstalled else {
            state = .noConnectMobile
            return
        }
        guard let device else {
            state = .noDevice
            return
        }
        let name = Self.name(of: device)
        guard ConnectIQ.sharedInstance().getDeviceStatus(device) == .connected else {
            state = .deviceOffline(name: name)
            return
        }
        // "Connected" is about the watch, not about our app on it. The app status is
        // asynchronous, so the optimistic answer stands until it comes back — a send that
        // turns out to be impossible fails with Garmin's own reason, which is better
        // wording than any guess made here.
        state = .ready(name: name)
        guard let app else { return }
        ConnectIQ.sharedInstance().getAppStatus(app) { [weak self] status in
            let installed = status?.isInstalled ?? false
            Task { @MainActor in self?.apply(appInstalled: installed, name: name) }
        }
    }

    private func apply(appInstalled: Bool, name: String) {
        guard case .ready = state else { return }
        state = appInstalled ? .ready(name: name) : .appNotRunning(name: name)
    }

    private static func name(of device: IQDevice) -> String {
        let friendly = device.friendlyName ?? ""
        if !friendly.isEmpty { return friendly }
        let model = device.modelName ?? ""
        return model.isEmpty ? "Garmin watch" : model
    }
}

// MARK: - SDK delegates

/// `nonisolated` throughout: the SDK gives no queue guarantee, so nothing here touches
/// state directly. Each callback pulls out the Sendable facts it needs — a name, a status,
/// a decoded card — and hops.
extension ConnectIQCompanionLink: IQDeviceEventDelegate {

    nonisolated func deviceStatusChanged(_ device: IQDevice!, status: IQDeviceStatus) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func deviceCharacteristicsDiscovered(_ device: IQDevice!) {
        Task { @MainActor in self.refresh() }
    }
}

extension ConnectIQCompanionLink: IQAppMessageDelegate {

    /// The card, arriving from another process on another device.
    ///
    /// Validation happens HERE, on the delegate thread, before anything crosses into the
    /// app: `CompanionSummary` either produces a whole valid card or throws, so nothing
    /// downstream ever holds a half-trusted payload. A rejection is counted and dropped in
    /// silence — the FIT is still coming, and it is the one that matters.
    nonisolated func received(_ message: Any!, from app: IQApp!) {
        guard let card = try? CompanionSummary(payload: message) else {
            Task { @MainActor in self.rejectedCards += 1 }
            return
        }
        Task { @MainActor in self.continuation.yield(card) }
    }
}

extension ConnectIQCompanionLink: IQUIOverrideDelegate {

    /// The SDK asks before sending the rider to the App Store. Answering "yes" without
    /// asking would be a shop opening itself in the middle of a session list.
    nonisolated func needsToInstallConnectMobile() {
        Task { @MainActor in self.state = .noConnectMobile }
    }
}

// MARK: - Remembering the watch

/// An `IQDevice` is three strings and a UUID, so the rider's choice survives a relaunch
/// without keeping an archived ObjC object around — one less thing to migrate when the
/// SDK's coding format changes under us.
private struct StoredDevice {
    var uuid: UUID
    var modelName: String
    var friendlyName: String

    private static let key = "companionDevice.v1"

    init(device: IQDevice) {
        uuid = device.uuid ?? UUID()
        modelName = device.modelName ?? ""
        friendlyName = device.friendlyName ?? ""
    }

    private init?(defaults: [String: String]) {
        guard let raw = defaults["uuid"], let uuid = UUID(uuidString: raw) else { return nil }
        self.uuid = uuid
        modelName = defaults["modelName"] ?? ""
        friendlyName = defaults["friendlyName"] ?? ""
    }

    var device: IQDevice {
        IQDevice(id: uuid, modelName: modelName, friendlyName: friendlyName)
    }

    func save() {
        UserDefaults.standard.set(["uuid": uuid.uuidString, "modelName": modelName,
                                   "friendlyName": friendlyName], forKey: Self.key)
    }

    static func load() -> StoredDevice? {
        guard let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: String]
        else { return nil }
        return StoredDevice(defaults: stored)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
