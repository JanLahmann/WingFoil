#if BETA
import Foundation
import WingFoilKit

/// The facts Ask CleanJibe is handed with a question — the kit builds them
/// (`AssistantState`, held to docs/copy/assistant/session-state.schema.json by its tests);
/// this only supplies what the app alone knows: its channel, version, build and the rider's units.
@MainActor
enum AskState {
    static func app(_ store: SessionStore) -> AssistantApp {
        let info = Bundle.main.infoDictionary
        let channel = switch AppChannel.channel {
        case .dev: "dev"
        case .beta: "beta"
        case .release: "release"
        }
        return AssistantApp(channel: channel,
                            appVersion: info?["CFBundleShortVersionString"] as? String ?? "0.0",
                            build: Int(info?["CFBundleVersion"] as? String ?? ""),
                            speed: store.speedUnit)
    }

    static func help(_ store: SessionStore) -> Data {
        AssistantState.help(app(store))
    }

    static func session(_ store: SessionStore, row: SessionRow, analysis: SessionAnalysis) -> Data {
        AssistantState.session(app(store), row: row, analysis: analysis)
    }
}
#endif
