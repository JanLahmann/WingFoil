// The Garmin link is a DEV channel door (docs/channels.md): the release and beta binaries
// carry no ConnectIQ framework, no Bluetooth code and no companion object at all. Gating the
// whole file — the `import ConnectIQ` included — is what makes that true of the binary and
// not merely of the UI. The kit's `CompanionLink` protocol stays compiled in every channel;
// it is this adapter that is dev-only.
#if DEV
import ConnectIQ
import Foundation
import OSLog
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

    /// Our CIQ app's UUIDs — the `id` attributes of the three watch manifests. The watch
    /// app and these constants are the same identity; change one and the link goes quiet
    /// with no error anywhere, because the SDK simply routes messages to an app nobody is
    /// running. There are three because the store keeps three builds of us apart: the
    /// release, the public-beta invite listing and the private dev listing each carry
    /// their own id, and a rider has exactly one of them on the wrist. "Send map failed
    /// (Failure_AppNotFound)" on a dev-beta watch (Jan, 13 Sep 2026) was this list being
    /// one entry long. The order is the order of preference when, improbably, more than
    /// one is installed.
    static let appUUIDs: [UUID] = [
        UUID(uuidString: "b1ef484c-77b9-4a69-b33d-18574f3bcbde")!,   // garmin/manifest.xml
        UUID(uuidString: "28942317-5a50-4fed-8a9e-d62f6847a2db")!,   // manifest-beta.xml (the open beta)
        UUID(uuidString: "953f7547-c152-42c2-8d33-69fb59ad0bf6")!,   // manifest-dev.xml (private dev)
    ]

    /// The scheme GCM reopens us on with the rider's device choice in the URL.
    ///
    /// Read out of the Info.plist rather than typed, because the dev channel is a second app
    /// beside the beta one (docs/channels.md) and two apps cannot share one custom scheme and
    /// stay predictable: whichever iOS feels like is the one that answers. `CJUrlSchemeCIQ`
    /// is `$(CJ_URL_SCHEME_CIQ)` in project.yml and sits in the very same plist as the
    /// `CFBundleURLTypes` entry that declares it, so the two can never drift apart.
    static let urlScheme = Bundle.main.object(forInfoDictionaryKey: "CJUrlSchemeCIQ")
        as? String ?? "wingfoil-ciq"

    /// Garmin Connect Mobile's own scheme, declared in `LSApplicationQueriesSchemes` —
    /// `canOpenURL` lies (returns false) for any scheme that is not declared there.
    private static let gcmScheme = "gcm-ciq"

    private(set) var state: CompanionLinkState = .noDevice

    private var device: IQDevice?
    /// One handle per known build, all registered for incoming cards: the watch does not
    /// say which build it is, and a card from the invite build must not be dropped because
    /// the phone was only listening for the release one.
    private var apps: [IQApp] = []
    /// The build the watch actually has — the one sends go to. Nil until a probe has found
    /// it; `transmit` probes on demand rather than guessing.
    private var app: IQApp?
    private let continuation: AsyncStream<CompanionSummary>.Continuation
    private let stream: AsyncStream<CompanionSummary>

    /// Cards that failed validation, counted rather than surfaced. A dropped card is
    /// invisible to the rider by design — the FIT is still coming — but a number that only
    /// ever goes up is the first thing to look at when the link "does not work".
    #if DEV
    /// The last link-probe page the watch delivered (docs/direct-transfer.md).
    private(set) var lastProbe: String?
    /// Raised on the main actor with each probe line, so a view can refresh — this class
    /// publishes nothing, and a row read off `lastProbe` alone never updated (19 Sep 2026).
    var onProbe: (@MainActor (String) -> Void)?
    #endif
    private(set) var rejectedCards = 0

    override init() {
        let (stream, continuation) = AsyncStream<CompanionSummary>.makeStream(
            bufferingPolicy: .unbounded)
        self.stream = stream
        self.continuation = continuation
        super.init()

        ConnectIQ.sharedInstance().initialize(withUrlScheme: Self.urlScheme,
                                              uiOverrideDelegate: self)
        // The direct transfer's two answers go out over this link and nowhere else, so the
        // inbox is handed them here rather than reaching for the SDK itself.
        DirectTransferInbox.shared.acknowledge = { [weak self] session, stream, page in
            self?.acknowledgeDirect(session: session, stream: stream, page: page)
        }
        DirectTransferInbox.shared.requestPages = { [weak self] session, stream, pages in
            self?.requestDirectPages(session: session, stream: stream, pages: pages)
        }
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
        // The wire format is the watch's `PhoneLink.KEY_IN_WIND`: one key, one integer,
        // and the watch refuses anything else (a Float there would silently relabel every
        // tack as a jibe for the rest of the session).
        let message: [String: Any] = ["wd": degreesFrom]
        try await transmit(message)
    }

    /// The map snapshot, built by `WatchMapMask.message` and sent unchanged.
    ///
    /// Nothing is inspected here beyond the size. A `sendMessage` payload to a device app
    /// is not a file transfer — Garmin's own limit is a few kilobytes and a payload over it
    /// comes back as a failure result on some firmware and, on others, as a success that
    /// never arrives. `WatchMapMask.maxBytes` is the ceiling the sender already respected;
    /// this is the belt to that pair of braces, so a future caller that skipped
    /// `WatchMapSender` cannot quietly push four kilobytes of city into the void.
    func sendMapSnapshot(_ message: sending [String: Any]) async throws {
        if let mask = message["mp"] as? Data, mask.count > WatchMapMask.maxBytes {
            throw CompanionLinkError.transmitFailed("mask too large (\(mask.count) bytes)")
        }
        try await transmit(message)
    }

    /// One message onto the radio, with Garmin's own failure word kept verbatim.
    private func transmit(_ message: sending [String: Any]) async throws {
        refresh()
        guard state.canSend else { throw CompanionLinkError.notReady(state) }
        // Which build is on the wrist is asked, not assumed: the answer is cached from the
        // last probe, and a first send waits the few hundred milliseconds for it rather
        // than firing at the release id and reading Failure_AppNotFound off a dev watch.
        if app == nil { app = await Self.installedApp(among: apps) }
        guard let app else {
            throw CompanionLinkError.transmitFailed("no CleanJibe build installed on the watch")
        }
        let result: IQSendMessageResult = await withCheckedContinuation { continuation in
            ConnectIQ.sharedInstance().sendMessage(message, to: app, progress: nil) { result in
                continuation.resume(returning: result)
            }
        }
        guard result == .success else {
            throw CompanionLinkError.transmitFailed(NSStringFromSendMessageResult(result))
        }
    }

    /// **The two answers the direct transfer sends back** (docs/transfer-format.md §3).
    ///
    /// Integers in, the dictionary built here: the inbox never holds a payload, so nothing
    /// un-`Sendable` crosses between it and the radio. Failure is swallowed on purpose — a
    /// page the watch was not acknowledged for is a page it sends again, which is exactly
    /// what an unacknowledged page should cause.
    func acknowledgeDirect(session: Int, stream: Int, page: Int) {
        Task { [weak self] in
            try? await self?.transmit(DirectPage.ack(sessionStartEpochS: session,
                                                     stream: stream, index: page))
        }
    }

    /// The need list, sent once the last page has arrived — the gaps, or nothing at all,
    /// which is what tells the watch it may free the stream.
    func requestDirectPages(session: Int, stream: Int, pages: [Int]) {
        Task { [weak self] in
            try? await self?.transmit(DirectPage.need(sessionStartEpochS: session,
                                                      stream: stream, pages: pages))
        }
    }

    /// The chosen watch's stable handle, for anything that has to remember what it already
    /// told *this* watch. Nil when no watch has been chosen.
    ///
    /// The UUID and not the friendly name: a rider renames a watch in Garmin Connect, and
    /// a cache keyed on the name would then re-send every mask it had already sent.
    var deviceKey: String? { device?.uuid?.uuidString }

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
        for app in apps { ConnectIQ.sharedInstance().unregister(forAppMessages: app, delegate: self) }
        device = nil
        apps = []
        app = nil
        StoredDevice.clear()
        state = .noDevice
    }

    private func adopt(_ device: IQDevice) {
        self.device = device
        apps = Self.appUUIDs.compactMap { IQApp(uuid: $0, store: nil, device: device) }
        app = nil
        ConnectIQ.sharedInstance().register(forDeviceEvents: device, delegate: self)
        // Registered unconditionally, not only when the watch is connected: the card
        // arrives on this callback the moment the rider is back in Bluetooth range, and
        // registering "once we are ready" would miss exactly that edge.
        for app in apps { ConnectIQ.sharedInstance().register(forAppMessages: app, delegate: self) }
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
        guard !apps.isEmpty else { return }
        let apps = self.apps
        Task { [weak self] in
            let found = await Self.installedApp(among: apps)
            self?.apply(installed: found, name: name)
        }
    }

    private func apply(installed: IQApp?, name: String) {
        app = installed
        guard case .ready = state else { return }
        state = installed != nil ? .ready(name: name) : .appNotRunning(name: name)
    }

    /// The first of `candidates` the watch reports as installed, in list order. Each probe
    /// is one asynchronous SDK call; they run one after another because the SDK's own
    /// queue serialises them anyway, and three is not a number worth a task group.
    private static func installedApp(among candidates: [IQApp]) async -> IQApp? {
        for candidate in candidates {
            let installed: Bool = await withCheckedContinuation { continuation in
                ConnectIQ.sharedInstance().getAppStatus(candidate) { status in
                    continuation.resume(returning: status?.isInstalled ?? false)
                }
            }
            if installed { return candidate }
        }
        return nil
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
    ///
    /// The selector is spelled out because the SDK does not check for it: the protocol
    /// method is `@optional`, so a Swift method whose name only *nearly* matches compiles
    /// without a word and the app aborts with "unrecognized selector" the first time the
    /// watch says anything. That first time was build 48, 13 Sep 2026, seconds after the
    /// phone started listening on the app id the watch actually has.
    @objc(receivedMessage:fromApp:)
    nonisolated func receivedMessage(_ message: Any!, from app: IQApp!) {
        #if DEV
        // The dev build's link probe (docs/direct-transfer.md): a page of bytes with its
        // size under "pr". Counted and sized here, never stored; the watch keeps the timing.
        if let dict = message as? [String: Any], let size = dict["pr"] as? Int {
            let seq = dict["q"] as? Int ?? 0
            let got: Int
            if let data = dict["b"] as? Data { got = data.count }
            else if let arr = dict["b"] as? [Any] { got = arr.count }
            else { got = -1 }
            os_log("link probe %d B #%d: %d bytes arrived", size, seq, got)
            Task { @MainActor in
                let line = "\(size / 1024) KB #\(seq): \(got) bytes arrived"
                self.lastProbe = line
                self.onProbe?(line)
            }
            return
        }
        // A page of the direct transfer (docs/transfer-format.md §3). Decoded HERE, on the
        // delegate thread, so that only a `Sendable` `DirectPage` crosses to the main actor
        // — the payload itself is an untyped ObjC dictionary and must not. The card path
        // below is untouched: a message is one or the other, told apart by its key.
        if let dictionary = message as? [AnyHashable: Any],
           dictionary[DirectPage.messageKey] != nil {
            do {
                let page = try DirectPage(payload: message)
                Task { @MainActor in DirectTransferInbox.shared.accept(page) }
            } catch {
                Task { @MainActor in DirectTransferInbox.shared.reject() }
            }
            return
        }
        #endif
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

#endif
