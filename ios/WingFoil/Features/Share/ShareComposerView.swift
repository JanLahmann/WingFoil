import PhotosUI
import SwiftUI
import WingFoilKit

/// The two ways one session leaves the phone: as a picture, or as the recording itself.
///
/// **The card** — pick an aspect, optionally drop one of your own photos behind it, export.
/// `PhotosPicker` runs out of process, so there is no photo-library permission prompt and
/// the app never gains access to anything the rider did not hand it. The picked image is
/// held in memory for the render and nothing is written anywhere until the share sheet
/// exports it.
///
/// **The file** — the archived `original.fit`, run through `FitShareFilter` so the copy
/// that leaves carries no serial number, no rider profile and no paired-accessory name.
/// The accelerometer stream is dropped by default: it is 95 % of the bytes, it is only
/// needed to recount pump strokes, and a 43 KB attachment goes through a chat app that a
/// 1 MB one does not.
///
/// The two live behind one switcher rather than two entry points because they answer the
/// same request — "send this to someone" — and the difference is only what the someone is
/// meant to do with it: look at it, or open it in an app of their own.
struct ShareComposerView: View {
    let row: SessionRow
    /// The already-loaded detail, when the screen has it: the card's outline then comes
    /// from geometry that is in memory rather than from a second FIT parse.
    var detail: SessionDetail?

    /// What the sheet is currently offering.
    private enum Payload: String, CaseIterable, Identifiable {
        case card, fit

        var id: String { rawValue }
        var label: String { self == .card ? "Card" : "FIT file" }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(ThumbnailStore.self) private var thumbnails
    @Environment(SessionStore.self) private var store

    @State private var payload = Payload.card
    @State private var shape = ShareCardStats.Shape.portrait
    /// How much of the key-metrics block the card carries. Seeded from the last card the
    /// rider exported (`ShareCardPresetStore`) and written back on every change — a
    /// preference, not a per-session choice, so a rider who wants lean cards asks once.
    @State private var preset = ShareCardPresetStore.load(from: .standard)
    @State private var pickedItem: PhotosPickerItem?
    @State private var photo: Image?
    @State private var photoFailed = false
    @State private var rendered: Image?
    /// Width the sheet has for the preview; 0 until the first layout pass.
    @State private var availableWidth: CGFloat = 0
    /// Off by default — see the type comment. Flipping it re-runs the scrub.
    @State private var includeAccelerometer = false
    @State private var fitFile: (url: URL, bytes: Int)?
    @State private var fitFailure: String?

    /// The title being typed, seeded with whatever the session is currently called. It drives
    /// the preview directly, so the card follows the keystrokes; the *row* follows the commit
    /// (`commit`), because a write per keystroke would be a database transaction per letter
    /// and a library reload behind it.
    @State private var titleDraft = ""
    /// The caption being typed, seeded from the row and clamped to `SessionNaming.noteLimit`
    /// as it is typed — the field refuses the 81st character rather than accepting it and
    /// silently dropping it on the way to the card.
    @State private var noteDraft = ""
    /// The last pair actually written through. Kept so `commit` can tell a real edit from the
    /// three or four times a focus change asks it to run — and so the FIT tab, whose work is a
    /// whole file rewrite, is keyed on *committed* names rather than on keystrokes.
    @State private var committedTitle = ""
    @State private var committedNote = ""
    /// Which field has the keyboard, watched only so that leaving one commits it: a rider who
    /// types a name and taps straight on "Share card" must not lose it, and `onSubmit` alone
    /// fires for neither a tap elsewhere nor a dismissed sheet.
    @FocusState private var focus: Field?

    private enum Field: Hashable { case title, note }

    /// The card's numbers *are* the app's key-metrics block, filtered by the preset — same
    /// model, same strings, one source (`ShareCardStats`). `metrics` is nil only while the
    /// analysis behind the sheet is still loading, which the card degrades for on its own.
    private var stats: ShareCardStats {
        ShareCardStats.make(row: row, title: displayTitle,
                            metrics: metrics, preset: preset,
                            note: noteDraft, timeZone: row.displayZone)
    }

    /// What the card is titled *right now* — the draft while it is being typed, the session's
    /// own name the moment it is emptied. Cleared means "give me the derived name back", and
    /// the preview has to show that immediately or a rider deleting a title watches the card
    /// go blank and puts the old one back.
    private var displayTitle: String {
        SessionNaming.title(custom: titleDraft, derived: SessionDisplay.derivedTitle(row))
    }

    private var metrics: KeyMetrics? {
        detail.map { KeyMetrics.make(summary: $0.analysis.summary,
                                     records: $0.analysis.records) }
    }

    /// Detail geometry when the session is open, the cached list thumbnail otherwise.
    private var thumbnail: TrackThumbnail? {
        detail?.shareOutline ?? thumbnails.thumbnail(for: row.id)
    }

    private var card: ShareCardView {
        ShareCardView(stats: stats, shape: shape, thumbnail: thumbnail, photo: photo)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    naming

                    Picker("Share", selection: $payload) {
                        ForEach(Payload.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch payload {
                    case .card: cardSection
                    case .fit: fitSection
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 28)
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                // The same `?` the session page's cards carry, following the switcher: a
                // rider on the card tab is asking about cards, one on the recording tab is
                // asking what leaves the phone. Both are topics nobody would ever go
                // looking for in the Help index, because you only wonder once you are here.
                ToolbarItem(placement: .primaryAction) {
                    HelpButton(topic: payload == .fit ? .shareFit : .shareCard,
                               size: .body)
                }
            }
            // The drafts are the row's, until the rider changes them. Seeded here rather than
            // in the property initializers because `row` is not available there.
            .onAppear {
                titleDraft = row.customTitle ?? ""
                noteDraft = row.shareNote ?? ""
                committedTitle = titleDraft
                committedNote = noteDraft
            }
            // Leaving a field is a commit. So is submitting one (below), and so is closing
            // the sheet — between them there is no way to type a name and not have it kept.
            .onChange(of: focus) { _, _ in commit() }
            .onDisappear { commit() }
            // Re-render whenever anything visible changes. `ImageRenderer` is main-actor
            // work, but a card is a handful of shapes and some text — cheap enough to redo
            // on a shape flip rather than caching two of them.
            .task(id: renderKey) { render() }
            .task(id: pickedItem) { await loadPhoto() }
            // The scrub is a full FIT rewrite, so it runs off the main actor and only for
            // the tab that needs it — opening the sheet on the card must not pay for it.
            .task(id: fitKey) { await prepareFIT() }
            #if DEBUG && targetEnvironment(simulator)
            // Screenshot hooks, same family as `UI_SHEET=share` that opened this sheet:
            // `simctl` can neither flip the switcher nor pick an aspect.
            .task {
                let environment = ProcessInfo.processInfo.environment
                if environment["UI_SHARE"] == "fit" { payload = .fit }
                if let raw = environment["UI_SHAPE"],
                   let wanted = ShareCardStats.Shape(rawValue: raw) { shape = wanted }
                // `UI_STATS=lean|complete` photographs the other preset without writing
                // the rider's stored choice, which a tap on the picker would.
                if let raw = environment["UI_STATS"],
                   let wanted = ShareCardStats.Preset(rawValue: raw) { preset = wanted }
                // `UI_TITLE` / `UI_CAPTION` photograph a *named* session without renaming the
                // rider's own: they seed the drafts and, by seeding `committed…` with the
                // same values, guarantee no commit follows. `simctl` cannot type.
                if let title = environment["UI_TITLE"] {
                    titleDraft = title
                    committedTitle = title
                }
                if let caption = environment["UI_CAPTION"] {
                    noteDraft = caption
                    committedNote = caption
                }
            }
            #endif
        }
    }

    // MARK: - Naming the session

    /// Two fields, above the switcher, because they belong to **both** things below it.
    ///
    /// **The title is a rename, not a card option.** Whatever is typed here becomes the
    /// session's name everywhere — the library row, the page header, the card, the clip's
    /// opening frame, the message that travels with the file, and the filename the file
    /// arrives under. One mental model: you are naming the afternoon. That is why the field
    /// sits above the Card/FIT switcher rather than inside the card tab, where it would read
    /// as a caption on one export.
    ///
    /// **The caption is not.** It is a line for whoever receives the picture, so it appears on
    /// the two artefacts that leave the phone — the card, under the date, and the clip's
    /// opening frame — and on no screen inside the app. A rider does not want "cold and
    /// glassy, finally got the tack" in his session list for ever.
    ///
    /// Empty means the derived name and no caption. Nothing here can leave the session
    /// nameless: clearing the title puts the recording's own name back in the placeholder, and
    /// the card follows immediately.
    private var naming: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                TextField(SessionDisplay.derivedTitle(row), text: $titleDraft)
                    .font(.headline)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focus, equals: .title)
                    .onSubmit { commit() }
                    .onChange(of: titleDraft) { _, new in
                        titleDraft = String(new.prefix(SessionNaming.titleLimit))
                    }
                Text("Names the session — the list, the card, the clip and the shared file "
                     + "all follow.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("Caption (optional)", text: $noteDraft)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($focus, equals: .note)
                    .onSubmit { commit() }
                    // Clamped as it is typed rather than on the way to the store: a field that
                    // accepts an 81st character and then drops it is a field that lies.
                    .onChange(of: noteDraft) { _, new in
                        noteDraft = String(new.prefix(SessionNaming.noteLimit))
                    }
                HStack(alignment: .firstTextBaseline) {
                    Text("One line on the card and on the clip's opening frame.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    // Only once it is worth knowing. A counter under an empty field is a
                    // limit announced before anybody has approached it.
                    if noteDraft.count >= SessionNaming.noteLimit - 20 {
                        Text("\(noteDraft.count)/\(SessionNaming.noteLimit)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(noteDraft.count >= SessionNaming.noteLimit
                                             ? .orange : .secondary)
                    }
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Writes both drafts through to the session row, if either has moved.
    ///
    /// Both store calls are no-ops when the normalized value already matches, so committing on
    /// every focus change, every submit and the sheet's dismissal costs nothing and means
    /// there is no path out of this screen that loses what was typed.
    private func commit() {
        let title = titleDraft, note = noteDraft
        guard title != committedTitle || note != committedNote else { return }
        committedTitle = title
        committedNote = note
        Task { @MainActor in
            await store.renameSession(row, to: title)
            await store.setShareNote(row, to: note)
        }
    }

    // MARK: - The card

    @ViewBuilder
    private var cardSection: some View {
        cardPreview
            .padding(.top, 4)

        Picker("Shape", selection: $shape) {
            ForEach(ShareCardStats.Shape.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)

        // Presets rather than eight checkboxes. The rider is choosing between "a picture
        // with the headline on it" and "the session, reported" — and a per-stat editor
        // would put a scrolling list of toggles in a sheet whose whole job is to be
        // finished in four taps. `Complete` is the default because the block it mirrors is
        // the one at the top of the session in the app.
        VStack(spacing: 4) {
            // The binding writes the preference itself rather than an `onChange` on the
            // state, so only a *tap* is remembered — the screenshot hook below sets the
            // same state and must not rewrite what the rider chose.
            Picker("Stats", selection: Binding(get: { preset },
                                               set: { chosen in
                                                   preset = chosen
                                                   ShareCardPresetStore.save(chosen,
                                                                             to: .standard)
                                               })) {
                ForEach(ShareCardStats.Preset.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Text(preset.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        photoControls

        if let rendered {
            ShareLink(item: rendered,
                      subject: Text(stats.title),
                      message: Text(cardCaption),
                      preview: SharePreview(stats.title, image: rendered)) {
                Label("Share card", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 44)
        }

        Text("The card is rendered at \(Int(shape.size.width)) × "
             + "\(Int(shape.size.height)) px. Nothing is uploaded — the image is "
             + "handed straight to the share sheet.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - The recording

    @ViewBuilder
    private var fitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Scrubbed before it leaves", systemImage: "person.crop.circle.badge.xmark")
                .font(.subheadline.weight(.semibold))
            Text("The copy you send carries the track, the speeds, the heart rate and every "
                 + "lap — but no watch serial number, no rider profile (name, weight, "
                 + "height) and no paired-accessory name. The original in your library is "
                 + "never touched.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))

        Toggle(isOn: $includeAccelerometer) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Include accelerometer data")
                Text("The 100 Hz stream is 95 % of the file and only needed to recount "
                     + "pump strokes. Off keeps the attachment small enough for a chat app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if let fitFile {
            ShareLink(item: fitFile.url,
                      subject: Text(displayTitle),
                      message: Text(invitation)) {
                Label("Share \(fitFile.url.lastPathComponent) · "
                      + "\(Fmt.bytes(Int64(fitFile.bytes)))",
                      systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else if let fitFailure {
            Label(fitFailure, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 44)
        }

        Text(invitation)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    /// Goes with the file, so a receiver with no app still has somewhere to open it: the
    /// web app reads the same FIT with the same engine, in a browser, without an account.
    ///
    /// It now leads with where and when, because the receiver is usually the friend who was
    /// on the water at the same time and could not otherwise tell *which* afternoon he had
    /// been sent. Composed in the kit (`ShareText`) rather than here, so the FIT, the clip and
    /// the card cannot drift into three different ways of naming one session.
    private var invitation: String {
        ShareText.fitMessage(place: displayTitle, startedAt: row.startDate,
                            timeZone: row.displayZone)
    }

    /// The card's own message. Short: a PNG is not something a receiver can re-analyse, and
    /// the card already carries the site in its footer pixels.
    private var cardCaption: String {
        ShareText.cardMessage(place: displayTitle, startedAt: row.startDate,
                             timeZone: row.displayZone)
    }

    private var renderKey: String {
        "\(shape.rawValue)|\(preset.rawValue)|\(photo == nil ? "plain" : "photo")"
            + "|\(thumbnail == nil ? 0 : 1)|\(metrics == nil ? 0 : 1)"
            + "|\(displayTitle)|\(noteDraft)"
    }

    /// Which tab is showing (so the scrub is never paid for on the card), whether the
    /// high-rate stream stays in — and the title, because it is the file's *name*: a rider who
    /// renames the session and then shares the recording must not send it under the old one.
    private var fitKey: String {
        "\(payload.rawValue)|\(includeAccelerometer)|\(committedTitle)"
    }

    /// The card at whatever size the sheet has room for.
    ///
    /// `ShareCardView` lays itself out at a *fixed* size — its export size over
    /// `renderScale` — because that is what makes the exported pixels land exactly on the
    /// shape's dimensions. A shape wider than the phone therefore has to be scaled down for
    /// the preview rather than made flexible: a card that reflowed to fit the sheet would
    /// not be the card that gets exported.
    ///
    /// The width is measured on the outer, full-width frame, so the measurement cannot
    /// chase the scale it feeds.
    private var cardPreview: some View {
        let scale = availableWidth > 0 ? min(1, availableWidth / card.size.width) : 1
        return card
            .clipShape(.rect(cornerRadius: 18))
            .shadow(radius: 10, y: 4)
            .scaleEffect(scale)
            .frame(width: card.size.width * scale, height: card.size.height * scale)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }

    /// The picker's label is built from a plain `String` captured *outside* the closure:
    /// `PhotosPicker` takes a sendable label builder, and reading `photo` inside it would
    /// be a main-actor access from a sendable context.
    private var photoPicker: some View {
        let title = photo == nil ? "Use a photo" : "Change photo"
        return PhotosPicker(selection: $pickedItem, matching: .images,
                            photoLibrary: .shared()) {
            Label(title, systemImage: "photo")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var photoControls: some View {
        HStack(spacing: 12) {
            photoPicker

            if photo != nil {
                Button(role: .destructive) {
                    photo = nil
                    pickedItem = nil
                } label: {
                    Label("Remove", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
            }
        }
        if photoFailed {
            Text("That image could not be read.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Work

    private func render() {
        let renderer = ImageRenderer(content: card)
        renderer.scale = ShareCardView.renderScale
        renderer.isOpaque = true
        if let image = renderer.uiImage {
            rendered = Image(uiImage: image)
        }
    }

    private func prepareFIT() async {
        guard payload == .fit else { return }
        fitFile = nil
        fitFailure = nil
        do {
            fitFile = try await store.shareableFIT(for: row, title: displayTitle,
                                                   includeAccelerometer: includeAccelerometer)
        } catch {
            fitFailure = "This recording cannot be shared: \(error)"
        }
    }

    private func loadPhoto() async {
        guard let pickedItem else { return }
        photoFailed = false
        guard let data = try? await pickedItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            photoFailed = true
            return
        }
        photo = Image(uiImage: image)
    }
}

extension SessionDetail {

    /// The card's track outline and its marks, built from geometry already in memory.
    ///
    /// Same normalization as the cached list thumbnails (`TrackThumbnail.outline`), so a
    /// session looks like itself in the list and on the card. The map series is thinned for
    /// MapKit (up to 6 000 vertices); a card at 1080 px wide cannot show more than a few
    /// hundred, so it is thinned again here.
    ///
    /// The marks come from the *same* two collections the map draws — `turnPins` (counted
    /// turns, on the verdict ladder) and `splashMarks` (the barometer's submersion
    /// evidence) — rather than from a second pass over the analysis, so a dot on the card
    /// and a dot on the map can only ever be the same event. They are projected through the
    /// outline's own projection, built from the same thinned coordinates, because a mark
    /// normalized against a different extent lands somewhere plausible and wrong.
    var shareOutline: TrackThumbnail {
        var coordinates: [(lat: Double, lon: Double, flying: Bool)] = []
        for segment in segments {
            for point in segment.points {
                coordinates.append((point.lat, point.lon, segment.flying))
            }
        }
        guard coordinates.count >= 2 else {
            return TrackThumbnail(points: [], speed: [], maxKn: 0)
        }
        let budget = TrackThumbnail.maxPoints * 2      // a card can carry more than a row
        let stride = max(1, (coordinates.count + budget - 1) / budget)
        var thinned: [(lat: Double, lon: Double, flying: Bool)] = []
        for (index, point) in coordinates.enumerated() {
            let phaseChange = thinned.last.map { $0.flying != point.flying } ?? true
            if index % stride == 0 || index == coordinates.count - 1 || phaseChange {
                thinned.append(point)
            }
        }
        return TrackThumbnail(points: TrackThumbnail.outline(coordinates: thinned),
                              marks: shareMarks(thinned),
                              speed: [], maxKn: maxSpeedKn)
    }

    private func shareMarks(
        _ thinned: [(lat: Double, lon: Double, flying: Bool)]) -> [TrackThumbnail.Mark] {
        guard let projection = TrackThumbnail.Projection(
            thinned.map { (lat: $0.lat, lon: $0.lon) }) else { return [] }

        func mark(_ lat: Double, _ lon: Double,
                  _ kind: TrackThumbnail.Mark.Kind) -> TrackThumbnail.Mark {
            let placed = projection.place(lat: lat, lon: lon)
            return TrackThumbnail.Mark(x: placed.x, y: placed.y, kind: kind)
        }

        var out = turnPins.map { pin -> TrackThumbnail.Mark in
            let kind: TrackThumbnail.Mark.Kind
            switch pin.outcome {
            case .fellIn: kind = .fellIn
            case .touchdown: kind = .touchdown
            case .flewThrough: kind = .flewThrough
            }
            return mark(pin.lat, pin.lon, kind)
        }
        out.append(contentsOf: splashMarks.map { mark($0.lat, $0.lon, .splash) })
        return out
    }
}
