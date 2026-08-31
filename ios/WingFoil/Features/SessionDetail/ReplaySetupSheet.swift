import PhotosUI
import SwiftUI
import WingFoilKit

/// Playback speeds, shared by the scrubber's inline picker and the clip's setup sheet.
///
/// One enum for both because they are one choice said twice: a rider who watched at 30× in
/// the card and then records at 60× is choosing against what he just saw, and two independent
/// definitions would let the two lists drift apart. 30× turns a two-hour session into four
/// minutes, which is about the pace at which a jibe is still recognisable.
enum ReplayRate: Double, CaseIterable, Identifiable {
    case x10 = 10, x30 = 30, x60 = 60

    var id: Double { rawValue }
    var label: String { "\(Int(rawValue))×" }
}

/// What a rider decides before a clip is made: how fast, and which of his own photos go in it.
///
/// **Why this stopped being a confirmation dialog.** The dialog was three buttons — "30× ·
/// about 34 s" and its two neighbours — and that was exactly right while a speed was the only
/// decision. Photos are not a fourth button: they are a picker, a set of thumbnails, a
/// statement about where each one will land, and a length that changes as they are added. An
/// action sheet cannot show any of that, and putting the picker *after* the dialog would mean
/// choosing a clip length before knowing what is in the clip.
///
/// It is still deliberately one screen with a start button on it. The rider is four taps from
/// a video and the sheet's job is to stay out of the way of that: a speed, optionally some
/// pictures, go.
struct ReplaySetupSheet: View {

    let detail: SessionDetail
    /// The commentary track, already filtered by the rider's toggle — the same list the
    /// cinema replay will caption and slow down for, and the one the length estimate is
    /// computed from.
    let milestones: [ReplayMilestone]
    let span: ClosedRange<Double>
    /// Called with the chosen speed and the loaded photos. The sheet dismisses itself first.
    let start: (Double, [ReplayPhoto]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var rate = ReplayRate.x30
    @State private var picked: [PhotosPickerItem] = []
    @State private var photos: [ReplayPhoto] = []
    @State private var loading = false
    /// Set when the picker handed back more items than could be read — see
    /// `ReplayPhotoLoader.load`.
    @State private var unreadable = 0

    /// The whole clip, as the kit sees it — the length under the picker, and the count of
    /// what will splice into the replay versus what plays at the end.
    private var storyboard: ReplayStoryboard {
        ReplayStoryboard.make(span: span, rate: rate.rawValue, milestones: milestones,
                              photos: photos.map(\.entry),
                              place: SessionDisplay.title(detail.row),
                              startedAt: detail.row.startDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    speedSection
                    photoSection
                    availabilityNote
                }
                .padding(.horizontal)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom) { startBar }
            .navigationTitle(ReplayRecorder.isAvailable ? "Record replay" : "Play replay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: picked.map(\.hashValue)) { await loadPhotos() }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Speed

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speed").font(.headline)
            Picker("Speed", selection: $rate) {
                ForEach(ReplayRate.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            // The speed is not what a rider is choosing between — the *clip length* is, and
            // it is neither `span / rate` (the slow-motion beats) nor the replay's own run
            // (the title card, the outro and every photo pause). `ReplayStoryboard` knows.
            Text("About \(Fmt.duration(storyboard.runWallS)) of video — "
                 + "\(Fmt.duration(storyboard.replayWallS)) of replay, plus the title and "
                 + "the closing card"
                 + (storyboard.photoWallS > 0
                    ? " and \(Fmt.duration(storyboard.photoWallS)) of photos." : "."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Photos

    @ViewBuilder
    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your photos").font(.headline)
                Spacer()
                if !photos.isEmpty {
                    Button("Remove all") {
                        picked = []
                        photos = []
                        unreadable = 0
                    }
                    .font(.caption)
                }
            }

            picker

            if loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 44)
            } else if !photos.isEmpty {
                thumbnails
                placementNote
            } else {
                Text("A photo taken during the session drops into the replay at the moment "
                     + "it was shot. One that cannot say when it was taken plays at the end, "
                     + "before the closing card. Up to \(ReplayPhotoLoader.maxCount).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if unreadable > 0 {
                Label("\(unreadable) picture\(unreadable == 1 ? "" : "s") could not be read "
                      + "and will not be in the clip.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Same out-of-process picker the share composer uses, and for the same reason: no
    /// photo-library permission prompt, and the app never sees anything the rider did not
    /// hand it. The label is built from a plain `String` captured *outside* the closure —
    /// `PhotosPicker` takes a sendable label builder, and reading `photos` inside it would be
    /// a main-actor access from a sendable context (`ShareComposerView` pays the same toll).
    private var picker: some View {
        let title = photos.isEmpty ? "Add photos" : "Change photos"
        return PhotosPicker(selection: $picked, maxSelectionCount: ReplayPhotoLoader.maxCount,
                            matching: .images, photoLibrary: .shared()) {
            Label(title, systemImage: "photo")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    /// The picked pictures, with the one thing about each that the rider cannot otherwise
    /// know: whether it landed *in* the session or at the end of the clip.
    private var thumbnails: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(photos) { photo in
                    VStack(spacing: 4) {
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(.rect(cornerRadius: 10))
                        Text(placement(of: photo))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// Where one photo ends up, in the replay's own elapsed clock — the same `m:ss` the
    /// scrubber's readout shows, so "3:12" on a thumbnail and "3:12" under the map are the
    /// same instant.
    private func placement(of photo: ReplayPhoto) -> String {
        guard let splice = storyboard.splices.first(where: { $0.photo == photo.id }) else {
            return "at the end"
        }
        return Fmt.clock(splice.t - span.lowerBound)
    }

    private var placementNote: some View {
        Text(placementSummary)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var placementSummary: String {
        var parts: [String] = []
        let spliced = storyboard.splices.count
        let slides = storyboard.slideshow.count
        if spliced > 0 { parts.append("\(spliced) in the replay") }
        if slides > 0 { parts.append("\(slides) at the end") }
        return parts.joined(separator: " · ")
    }

    // MARK: - The rest

    /// The one thing the rider has to be told before tapping start, and it is different on a
    /// phone that cannot capture.
    private var availabilityNote: some View {
        Text(ReplayRecorder.isAvailable
             ? "The replay plays itself full screen and the screen is recorded. The countdown "
               + "is not in the clip — recording starts on the title card. Pinch and drag the "
               + "map while it plays; a tap brings up the stop button."
             : "Screen recording is not available right now — Low Power Mode, AirPlay and "
               + "screen mirroring all switch it off. The replay will play full screen "
               + "without being recorded.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var startBar: some View {
        Button {
            let chosen = photos
            let speed = rate.rawValue
            dismiss()
            start(speed, chosen)
        } label: {
            Label(ReplayRecorder.isAvailable
                  ? "Record · about \(Fmt.duration(storyboard.runWallS))"
                  : "Play · about \(Fmt.duration(storyboard.runWallS))",
                  systemImage: ReplayRecorder.isAvailable ? "record.circle" : "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(loading)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func loadPhotos() async {
        guard !picked.isEmpty else {
            photos = []
            unreadable = 0
            return
        }
        loading = true
        let loaded = await ReplayPhotoLoader.load(picked)
        guard !Task.isCancelled else { return }
        photos = loaded
        unreadable = min(picked.count, ReplayPhotoLoader.maxCount) - loaded.count
        loading = false
    }
}
