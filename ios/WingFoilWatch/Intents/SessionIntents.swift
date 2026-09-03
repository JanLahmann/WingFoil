import AppIntents
import Foundation

/// "Hey Siri, start a CleanJibe session."
///
/// **Why the intents live in the app target and not in an extension.** An App Intents
/// extension runs in its own process, and this intent's whole job is to move a state machine
/// that owns an `HKWorkoutSession` — which exists in the app process and nowhere else. Shipped
/// as an extension it would have to message the app to do the thing, which is the app doing
/// the thing with a round trip in front of it. `openAppWhenRun` is the supported way to say
/// "run me in the app", and it is also the honest one here: the rider who says this out loud
/// wants his watch to be recording and showing him that it is.
struct StartSessionIntent: AppIntent {

    static var title: LocalizedStringResource { "Start a CleanJibe session" }

    // One string literal, not a concatenation: `IntentDescription` takes a
    // `LocalizedStringResource`, which is a literal or nothing.
    static var description: IntentDescription {
        IntentDescription("Records a wingfoil session on your Apple Watch — GPS, heart rate and wrist motion — with water lock on.")
    }

    /// The app is the only place a workout session can be started, so the app is where this
    /// runs. It is also what puts the recording screen in front of the rider without a tap.
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let recorder = SessionRecorder.shared
        // Guard against the double start, and say which one it is: "already recording" is a
        // useful answer, "OK" over a session that was already running is a lie by omission.
        guard !recorder.isSessionActive else {
            return .result(dialog: "A CleanJibe session is already running.")
        }
        recorder.startFromOutside()
        return .result(dialog: "Recording. Water lock is on — hold the crown to unlock.")
    }
}

/// "Hey Siri, stop my CleanJibe session."
///
/// Also `openAppWhenRun`: stopping writes the workout to Health, assembles the `.cjw`
/// container and hands it to WatchConnectivity, and the rider should see the summary that
/// results rather than hear a sentence about it and wonder.
struct StopSessionIntent: AppIntent {

    static var title: LocalizedStringResource { "Stop my CleanJibe session" }

    static var description: IntentDescription {
        IntentDescription("Ends the wingfoil session your Apple Watch is recording and saves it for your iPhone.")
    }

    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard SessionRecorder.shared.stopFromOutside() else {
            return .result(dialog: "No CleanJibe session is recording.")
        }
        return .result(dialog: "Saving your session.")
    }
}

/// The phrases Siri accepts without the rider setting anything up.
///
/// Every phrase has to contain `\(.applicationName)`, which resolves to `CFBundleDisplayName`
/// — CleanJibe, not the target name. That is the whole reason the display name was set: the
/// rider says the brand, and the identifiers underneath stay identifiers.
struct CleanJibeShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSessionIntent(),
            phrases: [
                "Start a \(.applicationName) session",
                "Start wingfoiling with \(.applicationName)",
                "Start recording with \(.applicationName)",
                "\(.applicationName) start"
            ],
            shortTitle: "Start session",
            systemImageName: "water.waves")

        AppShortcut(
            intent: StopSessionIntent(),
            phrases: [
                "Stop my \(.applicationName) session",
                "Stop recording with \(.applicationName)",
                "\(.applicationName) stop"
            ],
            shortTitle: "Stop session",
            systemImageName: "stop.circle")
    }
}
