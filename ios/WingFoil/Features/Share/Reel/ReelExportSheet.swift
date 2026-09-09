import AVKit
import SwiftUI
import WingFoilKit

/// Where a rider asks for a session video and watches it being made.
///
/// Three states in one sheet — the picker, the progress bar, the finished file — because
/// they are three moments of one action and a rider who has just waited twenty seconds
/// should not have to find a second screen to get the thing he waited for.
///
/// Not dev-only. A share card, a shared FIT and a session video are the same kind of thing:
/// something a rider makes to show somebody. The `#if TUNING` line is for thresholds.
struct ReelExportSheet: View {

    let detail: SessionDetail
    let title: String

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var store

    @State private var length = ReelPlan.Length.standard
    @State private var model = ReelExportModel()

    private var stage: ReelExportModel.Stage { model.stage }
    private var progress: Double { model.progress }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Length", selection: $length) {
                        ForEach(ReelPlan.Length.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isBusy)
                } header: {
                    Text("Length")
                } footer: {
                    Text("The whole session draws over the cut, slowing down at every jibe, "
                         + "record and the longest flight's takeoff, and speeding up between "
                         + "them. The last three seconds are the key-metrics card.")
                }

                switch stage {
                case .picking:
                    Section {
                        Button {
                            start()
                        } label: {
                            Label("Export video · \(length.label)", systemImage: "film")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                case .staging, .rendering:
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            ProgressView(value: stage == .staging ? 0 : progress)
                                .progressViewStyle(.linear)
                            Text(stage == .staging
                                 ? "Taking the map…"
                                 : "Drawing \(Int(progress * 100)) %")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Button(role: .destructive) { cancel() } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                    }
                case .done(let url):
                    Section {
                        VideoPlayer(player: AVPlayer(url: url))
                            .aspectRatio(9.0 / 16, contentMode: .fit)
                            .frame(maxHeight: 420)
                            .clipShape(.rect(cornerRadius: 12))
                            .listRowInsets(EdgeInsets())
                        ShareLink(item: url, subject: Text(title), message: Text(caption)) {
                            Label("Share video", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Button { model.reset() } label: {
                            Label("Make another", systemImage: "arrow.counterclockwise")
                        }
                    } footer: {
                        Text("\(length.label) · \(Fmt.bytes(ReelRenderer.size(of: url))) · "
                             + url.lastPathComponent)
                    }
                case .failed(let reason):
                    Section {
                        Label(reason, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Button("Try again") { model.reset() }
                    }
                }
            }
            .navigationTitle("Session video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.disabled(isBusy)
                }
            }
            .interactiveDismissDisabled(isBusy)
        }
        .onDisappear {
            model.cancel()
            // The share sheet has already taken a copy of anything it was handed.
            ReelRenderer.clearCache()
        }
        #if DEBUG && targetEnvironment(simulator)
        .task {
            // `UI_EXPORT_REEL_LENGTH=15|20|30` picks the cut for a headless render; the hook
            // that opens this sheet at all is `UI_EXPORT_REEL` (SessionDetailView).
            if let raw = ProcessInfo.processInfo.environment["UI_EXPORT_REEL_LENGTH"],
               let picked = Int(raw).flatMap(ReelPlan.Length.init(rawValue:)) {
                length = picked
            }
        }
        #endif
    }

    private var isBusy: Bool { model.isBusy }

    private var caption: String {
        ShareText.clipMessage(place: title, startedAt: detail.row.startDate,
                              timeZone: detail.row.displayZone)
    }

    // MARK: - Running it

    private func start() {
        model.start(detail: detail, title: title, style: store.mapStyle,
                    visibility: store.mapLayers(for: .ride), length: length)
    }

    private func cancel() { model.cancel() }
}

/// The export's state and the task that drives it.
///
/// A model rather than `@State` on the view for one concrete reason: the renderer reports
/// progress from the encoder's own thread, so the thing it reports *to* has to be something
/// a `@Sendable` closure may capture. A `@MainActor` class is; a `View` struct's bindings
/// are not.
@MainActor
@Observable
final class ReelExportModel {

    enum Stage: Equatable {
        case picking
        /// The map snapshot and the closing card, before a single frame is encoded. Its own
        /// stage because it is main-actor work with no progress to report, and a bar that
        /// sits at zero for two seconds reads as a hang.
        case staging
        case rendering
        case done(URL)
        case failed(String)
    }

    private(set) var stage = Stage.picking
    private(set) var progress: Double = 0
    private var job: Task<Void, Never>?

    var isBusy: Bool { stage == .staging || stage == .rendering }

    func reset() {
        stage = .picking
        progress = 0
    }

    func start(detail: SessionDetail, title: String, style: MapStyleChoice,
               visibility: MapLayerVisibility, length: ReelPlan.Length) {
        job?.cancel()
        stage = .staging
        progress = 0
        let output = ReelRenderer.destination(for: detail.row)

        job = Task { [weak self] in
            guard let scene = await ReelScene.make(detail: detail, title: title, style: style,
                                                   visibility: visibility, length: length)
            else {
                self?.fail(ReelRenderer.Failure.noTrack)
                return
            }
            guard let self, !Task.isCancelled else { return }
            stage = .rendering

            // Off the main actor from here: six hundred frames of Core Graphics on the main
            // thread would freeze the very bar that is reporting them.
            let result = await Task.detached(priority: .userInitiated) {
                Result { try ReelRenderer.render(scene, to: output) { done in
                    Task { @MainActor in self.report(done) }
                } }
            }.value

            guard !Task.isCancelled else { return }
            switch result {
            case .success(let url):
                progress = 1
                stage = .done(url)
            case .failure(let error):
                if case ReelRenderer.Failure.cancelled = error { return }
                fail(error)
            }
        }
    }

    func cancel() {
        job?.cancel()
        job = nil
        reset()
    }

    /// Every frame reports; only a whole percent moves the bar. Six hundred observable
    /// writes for a bar a few hundred points wide is six hundred view updates nobody sees.
    fileprivate func report(_ done: Double) {
        guard done >= progress + 0.01 || done >= 1 else { return }
        progress = done
    }

    private func fail(_ error: any Error) {
        stage = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
    }
}
