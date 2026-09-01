import SwiftUI

/// The CleanJibe watch recorder.
///
/// One job: capture a wingfoil session honestly — GPS with the receiver's own Doppler speed,
/// heart rate, and the wrist accelerometer at 50 Hz — and hand it to the iPhone, where
/// WingFoilKit's analysis engine does the rest. No flight detection, no turn detection and no
/// records on the wrist; those live in exactly one implementation and it is not this one.
///
/// The target is named `WingFoilWatch` and its bundle id is
/// `de.lahmann.wingfoil.watchkitapp`, both of which are identifiers rather than the brand.
/// `CFBundleDisplayName` is CleanJibe, and that is what the rider reads.
@main
struct WingFoilWatchApp: App {

    @State private var recorder = SessionRecorder()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(recorder)
                .task {
                    // Permissions, the WatchConnectivity session, and a sweep for anything a
                    // previous launch left behind. Idempotent — a rider who opens the app
                    // four times before launching gets one of each.
                    recorder.prepare()
                }
        }
    }
}
