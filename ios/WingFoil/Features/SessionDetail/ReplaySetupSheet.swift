import PhotosUI
import SwiftUI
import WingFoilKit

/// Playback speeds for the **scrubber's** inline picker — the one on the session page, next
/// to the play button.
///
/// It stayed a speed picker when the clip's setup sheet became a length picker, and the
/// difference is what the two controls are for. Scrubbing is *browsing*: the rider is looking
/// for the jibe he remembers, the run has no end he is planning around, and "how fast does
/// this go past" is exactly the question. A clip has a length and an audience, and nobody
/// chooses one by its rate — see `ReplayClipLength`.
enum ReplayRate: Double, CaseIterable, Identifiable {
    case x10 = 10, x30 = 30, x60 = 60

    var id: Double { rawValue }
    var label: String { "\(Int(rawValue))×" }
}

/// How long the clip should be.
///
/// **Why this replaced the rate picker.** The sheet used to offer 10× / 30× / 60× and print
/// the length underneath each. Nobody was choosing a rate: the eye went to the seconds, and
/// the seconds were what the decision was about — which is why the same 30× meant a 34-second
/// clip on one afternoon and four minutes on the next. So the picker offers the thing that is
/// actually being chosen, and `ReplayPacing` works the speed out.
///
/// Ten and twenty-five seconds because that is what a clip in a chat app is: the two-minute
/// version was watched by nobody. Sixty for a session worth a longer look. And **Full
/// detail**, which is deliberately *not* a length — it is the old 10×, kept for the rider who
/// wants to watch the afternoon rather than post it, and it is the one choice whose clip gets
/// longer as the session does.
enum ReplayClipLength: String, CaseIterable, Identifiable {
    case s10, s25, s60, full

    var id: String { rawValue }

    var label: String {
        switch self {
        case .s10: "10 s"
        case .s25: "25 s"
        case .s60: "60 s"
        case .full: "Full detail"
        }
    }

    /// Wall seconds of *replay* this asks for, or nil for "full detail", which asks for a
    /// pace instead. The two cards and the photo pauses are added on top of it by
    /// `ReplayStoryboard` — see its `runWallS`.
    var targetWallS: Double? {
        switch self {
        case .s10: 10
        case .s25: 25
        case .s60: 60
        case .full: nil
        }
    }

    /// The pace "Full detail" means: the rate the picker's slowest option used to be, which is
    /// where the pinned 77.7 s Torbole run comes from.
    static let fullDetailRate: Double = 10

    /// The rate and ease this choice resolves to for one session.
    func pacing(span: ClosedRange<Double>, milestones: [ReplayMilestone]) -> ReplayPacing.Plan {
        guard let targetWallS else {
            return ReplayPacing.Plan(rate: Self.fullDetailRate, ease: .cinema)
        }
        return ReplayPacing.plan(span: span, targetWallS: targetWallS,
                                 easeAt: milestones.map(\.t))
    }
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
    /// Called with the resolved pacing, the chosen frame and the loaded photos. The sheet
    /// dismisses itself first.
    let start: (ReplayPacing.Plan, ReplayFraming, [ReplayPhoto]) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Only for the remembered length — the one thing on this sheet that belongs to the rider
    /// rather than to this session.
    @Environment(SessionStore.self) private var store

    @State private var length = ReplayClipLength.s25
    @State private var framing = ReplayFraming.fullScreen
    @State private var picked: [PhotosPickerItem] = []
    @State private var photos: [ReplayPhoto] = []
    @State private var loading = false
    /// Set when the picker handed back more items than could be read — see
    /// `ReplayPhotoLoader.load`.
    @State private var unreadable = 0

    /// What the chosen length comes out at on *this* session — a rate, and (on a short target
    /// with a talkative afternoon) briefer slow-motion dips. See `ReplayPacing`.
    private var pacing: ReplayPacing.Plan {
        length.pacing(span: span, milestones: milestones)
    }

    /// The whole clip, as the kit sees it — the length under the picker, and the count of
    /// what will splice into the replay versus what plays at the end.
    private var storyboard: ReplayStoryboard {
        let plan = pacing
        return ReplayStoryboard.make(span: span, rate: plan.rate, milestones: milestones,
                                     photos: photos.map(\.entry),
                                     place: SessionDisplay.title(detail.row),
                                     startedAt: detail.row.startDate,
                                     timeZone: detail.row.displayZone, ease: plan.ease)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    lengthSection
                    framingSection
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
            // The sheet opens on the length the last clip was made at — the second clip of an
            // afternoon is nearly always the same shape as the first.
            .onAppear {
                length = store.replayClipLength
                framing = store.replayFraming
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Length

    /// The picker, and one sentence that adds up out loud.
    ///
    /// The sentence is the whole reason the inversion is safe. "10 s" on the button is the
    /// length of the *replay*; the clip is that plus a title card, a closing card and every
    /// photo pause, and a rider who added three photos and then found a 24-second video where
    /// the button said 10 would rightly stop trusting the button. So the total leads, and the
    /// parts it is made of follow — including the derived speed, which is what the finished
    /// video's own corner chip will say.
    private var lengthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Length").font(.headline)
            Picker("Length", selection: $length) {
                ForEach(ReplayClipLength.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(lengthNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lengthNote: String {
        var sentence = "About \(Fmt.duration(storyboard.runWallS)) of video — "
            + "\(Fmt.duration(storyboard.replayWallS)) of replay at about "
            + "\(Int(pacing.rate.rounded()))×, plus the title and the closing card"
        if storyboard.photoWallS > 0 {
            sentence += " and \(Fmt.duration(storyboard.photoWallS)) of photos"
        }
        sentence += "."
        // The one case where the button cannot keep its promise: a very long session squeezed
        // into a very short clip would need a speed at which the dot stops reading as a moving
        // boat, so the rate is capped and the clip comes out longer. Said, not hidden.
        if let target = length.targetWallS, storyboard.replayWallS > target + 0.5 {
            sentence += " This session is too long to fit \(Fmt.duration(target)) without the "
                + "replay becoming a slideshow, so it runs at the fastest speed the map can "
                + "still animate."
        }
        return sentence
    }

    // MARK: - Shape

    /// What shape the video should be — the same decision the share card's aspect picker is,
    /// and the same words on it.
    ///
    /// **Full screen is the default and stays the default.** It is the only choice that needs
    /// no export at all (the recorder already produces it), it is what every clip made before
    /// this existed looks like, and it is what a failed crop falls back to. The three ratios
    /// are for a rider who knows where the clip is going.
    private var framingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shape").font(.headline)
            Picker("Shape", selection: $framing) {
                ForEach(ReplayFraming.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(framingNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var framingNote: String {
        switch framing {
        case .fullScreen:
            "The whole screen, exactly as the phone records it — no cropping, nothing to go "
                + "wrong."
        default:
            "\(framing.name) — the replay plays inside a \(framing.label) frame and the rest "
                + "of the screen is painted out, so you can see what the clip will be while "
                + "you record it. The video is cropped to that frame afterwards."
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
            let plan = pacing
            // Remembered here rather than on every tap of the picker: a rider who opened the
            // sheet, tried the three lengths and cancelled has not changed his mind about
            // anything. The choice is made by starting.
            store.replayClipLength = length
            store.replayFraming = framing
            dismiss()
            start(plan, framing, chosen)
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
        let loaded = await ReplayPhotoLoader.load(picked, sessionZone: detail.row.displayZone)
        guard !Task.isCancelled else { return }
        photos = loaded
        unreadable = min(picked.count, ReplayPhotoLoader.maxCount) - loaded.count
        loading = false
    }
}
