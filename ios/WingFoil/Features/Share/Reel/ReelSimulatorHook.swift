#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftUI
import WingFoilKit

/// `UI_EXPORT_REEL=1` — render a session video headlessly and leave it in the app's
/// Documents directory, where `xcrun simctl get_app_container … data` can reach it.
///
/// **Why a hook and not "tap the button".** `simctl` cannot tap, and this is the one feature
/// in the app whose output is a file rather than a screen: a screenshot of the export sheet
/// proves the sheet exists and proves nothing at all about the twenty seconds of video it
/// makes. With the hook a Mac can render a reel, pull the .mp4 out of the container and look
/// at three frames of it — which is how the overlays' positions, the scrim's weight and the
/// end card's fit were actually settled.
///
/// This is also the reason the renderer is offscreen rather than a screen capture: the
/// cinema clip's `RPScreenRecorder` writes a zero-byte file in the Simulator
/// (docs/testing.md), so nothing about *it* can be checked on a Mac.
enum ReelHook {

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["UI_EXPORT_REEL"] == "1"
    }

    private static var length: ReelPlan.Length {
        ProcessInfo.processInfo.environment["UI_EXPORT_REEL_LENGTH"]
            .flatMap { Int($0) }
            .flatMap(ReelPlan.Length.init(rawValue:)) ?? .standard
    }

    /// Renders and writes `reel.mp4` into Documents, printing the wall time it took and the
    /// file's size so a headless run leaves evidence in the log as well as on disk.
    @MainActor
    static func run(detail: SessionDetail, title: String, store: SessionStore) async {
        let started = Date()
        guard let scene = await ReelScene.make(detail: detail, title: title,
                                               style: store.mapStyle,
                                               visibility: store.mapLayers(for: .ride),
                                               length: length) else {
            print("[reel] no scene — this session has no track")
            return
        }
        let staged = Date()
        let output = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("reel.mp4")
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                try ReelRenderer.render(scene, to: output)
            }.value
            let bytes = ReelRenderer.size(of: url)
            print(String(format: "[reel] %@ · %d frames · stage %.1f s · encode %.1f s · %d bytes",
                         url.lastPathComponent, scene.plan.frameCount,
                         staged.timeIntervalSince(started), Date().timeIntervalSince(staged),
                         bytes))
        } catch {
            print("[reel] failed: \(error)")
        }
    }
}
#endif
