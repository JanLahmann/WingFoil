import BackgroundTasks
import Foundation
import UserNotifications
import WingFoilKit

/// "Tell me when a new session shows up", the way Waterspeed does it — except there is no
/// server to push from, so the phone asks intervals.icu itself.
///
/// One `BGAppRefreshTask`: iOS wakes the app when it feels like it (see the caveats in the
/// settings footer), the app lists the last few days of activities, and anything it has not
/// seen before and does not already own becomes a local notification. Every decision in
/// that sentence is `NewActivityWatch` in WingFoilKit, where it is tested; this file is the
/// glue — scheduling, the notification centre, and the tap that opens the session.
///
/// The FIT is pulled and analysed afterwards, best effort, so that tapping the banner most
/// often lands on a finished analysis rather than on a spinner. Notification first: iOS can
/// pull the plug on the wake at any moment, and the one thing that must survive that is the
/// rider being told.
@MainActor
final class ActivityNotifier: NSObject {

    // `nonisolated` because the notification-centre delegate reads them from whatever
    // thread iOS delivers a tap on.
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in project.yml.
    nonisolated static let taskIdentifier = "de.lahmann.wingfoil.refresh"
    /// The rider's toggle (Settings → Notifications). Off until he asks.
    nonisolated static let enabledKey = "notifyOnNewActivities"
    /// Set the one time the app offers the feature by itself (`NewActivityPrompt`), so the
    /// offer is made once per install and never again — whatever the answer was.
    nonisolated static let promptedKey = "notifyPromptShown.v1"
    /// Set by a background prefetch so the next foreground knows the library moved under it.
    nonisolated static let pendingImportKey = "backgroundImportPending"
    nonisolated static let markKey = "newActivityMark.v1"
    nonisolated static let activityIdKey = "icuActivityId"

    /// What we ask for. iOS treats it as a hint and will give less (or nothing) depending
    /// on battery, Low Power Mode and how often the app is actually opened.
    static let interval: TimeInterval = 30 * 60

    static let shared = ActivityNotifier()

    /// Strong on purpose: the store lives as long as the app does, and the background wake
    /// needs it at a moment when no view is on screen to hold it.
    private var store: SessionStore?

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    // MARK: - Launch

    /// Registration has to happen before the app finishes launching, and unconditionally:
    /// an identifier in `BGTaskSchedulerPermittedIdentifiers` that nothing registers for is
    /// a launch-time exception. Whether a task is ever *scheduled* is the toggle's business.
    func register(store: SessionStore) {
        self.store = store
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier,
                                        using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                return task.setTaskCompleted(success: false)
            }
            // The launch handler runs on a queue of BGTaskScheduler's choosing, so hop
            // rather than assume. The expiration handler is installed on the other side of
            // this hop, microseconds later and well inside the ~30 s the system allows.
            let box = TaskBox(refresh)
            Task { @MainActor in ActivityNotifier.shared.handle(box.task) }
        }
        // A relaunch is also the moment to make sure a request is outstanding: iOS drops
        // every pending request when the app is force-quit or updated.
        schedule()
    }

    /// Asks for the next wake. No-op while the toggle is off, so a rider who never enables
    /// the feature never has a background task at all.
    func schedule() {
        guard isEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // `.notPermitted` in the simulator and whenever Background App Refresh is off
            // system-wide. Neither is worth a banner: the settings footer already says so.
        }
    }

    // MARK: - The toggle

    /// Authorization is asked for here rather than at launch: the rider has just said he
    /// wants notifications, which is the only moment the system prompt is answerable.
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        return granted
    }

    func enable() {
        // A fresh start: the first poll after enabling seeds silently rather than
        // announcing whatever happened while the feature was off (`NewActivityWatch`).
        UserDefaults.standard.removeObject(forKey: Self.markKey)
        schedule()
    }

    func disable() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        UserDefaults.standard.removeObject(forKey: Self.markKey)
    }

    // MARK: - The wake

    private func handle(_ task: BGAppRefreshTask) {
        // Chain the next one first. A wake that throws must not be the last wake.
        schedule()
        let box = TaskBox(task)
        let work = Task { @MainActor in
            let success = await self.poll()
            box.task.setTaskCompleted(success: success)
        }
        // iOS is done with us: cancelling the task stops the prefetch at its next
        // suspension point, and `poll` still gets to report and finish.
        task.expirationHandler = { work.cancel() }
    }

    /// One poll. Returns whether it got as far as talking to intervals.icu — that is what
    /// `setTaskCompleted(success:)` means to the scheduler's own budgeting.
    @discardableResult
    func poll() async -> Bool {
        guard isEnabled, let store else { return false }
        let key = store.apiKey
        guard !key.isEmpty else { return false }
        let ingestor = store.ingestor
        let mark = Self.loadMark()
        let now = Date()

        guard let (decision, activities) = await list(key: key, mark: mark, now: now,
                                                      ingestor: ingestor) else { return false }
        for notice in decision.notices { await post(notice) }
        Self.save(decision.mark)
        guard !decision.notices.isEmpty, !Task.isCancelled else { return true }

        // Best effort from here on. Whatever lands is a session already analysed by the
        // time the rider taps; whatever does not simply imports on the tap instead.
        let imported = await prefetch(decision.notices, from: activities,
                                      key: key, ingestor: ingestor)
        if imported > 0 {
            UserDefaults.standard.set(true, forKey: Self.pendingImportKey)
        }
        return true
    }

    /// The network half, off the main actor. `nonisolated` rather than `Task.detached` so
    /// the expiration handler's cancellation reaches it.
    private nonisolated func list(key: String, mark: NewActivityMark, now: Date,
                                  ingestor: SessionIngestor)
    async -> (NewActivityWatch.Decision, [IcuActivity])? {
        let client = IcuClient(apiKey: key)
        do {
            let activities = try await client.activities(
                oldest: NewActivityWatch.windowStart(mark: mark, now: now), newest: now)
            // Deleted sessions count as "already accounted for" here, which is the only
            // honest way to file them: `IcuSyncService.fetchOne` would refuse to import a
            // tombstoned activity anyway, so without this the poller would post a banner for
            // a session it then declines to fetch — the resurrection happening in the
            // notification tray instead of the library.
            var library = try await ingestor.allSessions().map(NewActivityWatch.KnownSession.init)
            library += try await ingestor.library.tombstones().map(\.asKnownSession)
            let decision = NewActivityWatch.evaluate(activities: activities, library: library,
                                                     mark: mark, now: now)
            return (decision, activities)
        } catch {
            return nil
        }
    }

    /// Downloads and ingests what was just announced, newest first, stopping the moment
    /// iOS takes the time back. Returns how many sessions actually landed.
    private nonisolated func prefetch(_ notices: [NewActivityNotice], from activities: [IcuActivity],
                                      key: String, ingestor: SessionIngestor) async -> Int {
        let service = IcuSyncService(client: IcuClient(apiKey: key), ingestor: ingestor)
        var imported = 0
        for notice in notices.reversed() {
            guard !Task.isCancelled else { break }
            guard let activity = activities.first(where: { $0.id == notice.activityId })
            else { continue }
            if case .imported = try? await service.fetchOne(activity) { imported += 1 }
        }
        return imported
    }

    private func post(_ notice: NewActivityNotice) async {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        if let subtitle = notice.subtitle { content.subtitle = subtitle }
        content.body = notice.body
        content.sound = .default
        content.userInfo = [Self.activityIdKey: notice.activityId]
        // Several sessions from one wake stack as one conversation rather than as a pile.
        content.threadIdentifier = "wingfoil.newSession"
        // Keyed by the activity, so the same session can never be announced twice even if
        // the mark were somehow lost.
        let request = UNNotificationRequest(identifier: "wingfoil.newSession.\(notice.activityId)",
                                            content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - The mark

    static func loadMark() -> NewActivityMark {
        guard let data = UserDefaults.standard.data(forKey: markKey),
              let mark = try? JSONDecoder().decode(NewActivityMark.self, from: data)
        else { return NewActivityMark() }
        return mark
    }

    static func save(_ mark: NewActivityMark) {
        guard let data = try? JSONEncoder().encode(mark) else { return }
        UserDefaults.standard.set(data, forKey: markKey)
    }

    /// True (once) when a background wake imported something while the app was away.
    static func consumePendingImport() -> Bool {
        guard UserDefaults.standard.bool(forKey: pendingImportKey) else { return false }
        UserDefaults.standard.removeObject(forKey: pendingImportKey)
        return true
    }

    /// A `BGTask` is not `Sendable` and never will be; the hop that carries it to the main
    /// actor is a hand-off, not sharing — nothing else ever touches it.
    private final class TaskBox: @unchecked Sendable {
        let task: BGAppRefreshTask

        init(_ task: BGAppRefreshTask) { self.task = task }
    }
}

// MARK: - Tapping the notification

extension ActivityNotifier: UNUserNotificationCenterDelegate {

    /// The tap. If the prefetch already imported the session it opens straight away;
    /// otherwise the ordinary intervals.icu sync runs first and then it opens.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler:
                                            @escaping () -> Void) {
        let activityId = response.notification.request.content
            .userInfo[Self.activityIdKey] as? String
        completionHandler()
        guard let activityId else { return }
        Task { @MainActor in
            await ActivityNotifier.shared.store?.openSession(icuActivityId: activityId)
        }
    }

    /// A wake cannot happen with the app in front, but a `poll()` from a debug build can —
    /// and a notification the rider never sees would look like a bug in the feature.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler:
                                            @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
