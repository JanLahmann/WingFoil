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
    /// The session's story (`SessionStory`), from the page that opened the sheet: the
    /// caption's lead and the card's "Best ever" ribbon, the same line and the same records
    /// the page draws over its block.
    var story: SessionStory?

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
    /// Shape, big number, background, photo, map and the rendered PNG — everything the card
    /// composer shares with the period card's (`ShareCardDesign`). What stays here is the
    /// session's own: its numbers, its outline, its ground, and a title that renames it.
    @State private var design = ShareCardDesign()
    /// The beta's counter fires once per composer, not once per re-render (`render`).
    @State private var countedCard = false
    /// The session video's own sheet — the picker, the progress bar and the finished file
    /// (`ReelExportSheet`). BETA, with the door that raises it.
    #if BETA
    @State private var showReel = false
    /// The analysis mail's own sheet, raised by the row under the switcher. BETA.
    @State private var showSendToDeveloper = false
    #endif
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

    /// The card's numbers *are* the app's key-metrics block, told as layout B v2 — same
    /// model, same strings, one source (`ShareCardStats`). `metrics` is nil only while the
    /// analysis behind the sheet is still loading, which the card degrades for on its own.
    private var stats: ShareCardStats {
        ShareCardStats.make(row: row, title: displayTitle,
                            metrics: metrics, hero: design.hero,
                            note: noteDraft,
                            // Settings → Speed records. A card is an all-time claim in a
                            // chat thread, so "Only verified" takes the record cell off a
                            // class-(c) card rather than sending it out marked.
                            policy: store.speedRecordPolicy,
                            timeZone: row.displayZone)
    }

    /// What the card is titled *right now* — the draft while it is being typed, the session's
    /// own name the moment it is emptied. Cleared means "give me the derived name back", and
    /// the preview has to show that immediately or a rider deleting a title watches the card
    /// go blank and puts the old one back.
    private var displayTitle: String {
        SessionNaming.title(custom: titleDraft, derived: SessionDisplay.derivedTitle(row))
    }

    private var metrics: KeyMetrics? {
        detail?.keyMetrics
    }

    /// Detail geometry when the session is open, the cached list thumbnail otherwise.
    private var thumbnail: TrackThumbnail? {
        detail?.shareOutline ?? thumbnails.thumbnail(for: row.id)
    }

    private var card: ShareCardView {
        ShareCardView(stats: stats, shape: design.shape, thumbnail: thumbnail,
                      photo: design.cardPhoto,
                      map: design.cardPhoto == nil ? design.map : nil,
                      recordBadge: story?.cardBadge,
                      onTrackFrame: { [design] in design.trackBox = $0 })
    }


    /// The track and its marks as **coordinates**, for the map snapshot: the same two
    /// collections `shareOutline` normalizes into the card's unit box, one step earlier.
    /// Nil when the session's geometry is not in memory — the cached list thumbnail has no
    /// degrees left in it, and a card cannot be given a map it cannot place a track on.
    private var mapSource: ShareCardMapSource? {
        detail?.shareGeography
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

                    // **The third thing this page can do**, under the switcher rather than
                    // inside it (Jan, 21 Sep 2026). The Card/FIT segments answer one
                    // request — send this to someone — and a third segment would make a
                    // rider choose between "share" and "report" before he has decided he
                    // wants either. A full-width row directly under the control is where
                    // he is already looking, and it carries the same afternoon whichever
                    // segment is showing.
                    //
                    // BETA (docs/channels.md): the App Store build has no row and no sheet.
                    #if BETA
                    sendToDeveloperRow
                    #endif

                    switch payload {
                    case .card: cardSection
                    case .fit: fitSection
                    }

                    // The one row in the app that reports a *session* rather than the app:
                    // it is here because "this card says 3 jibes and there were 5" is a
                    // thought a rider has while looking at the card, and the mail leaves
                    // with that card attached and the session's own stamp in the text.
                    FeedbackMailRow(title: FeedbackDoors.share,
                                    systemImage: "exclamationmark.bubble",
                                    session: row, card: { design.renderedImage?.pngData() })
                        .font(.footnote)
                        .padding(.top, 4)
                }
                .padding(.horizontal)
                .padding(.bottom, 28)
                // The composer is one column — two fields, a switcher, the preview, the
                // share button — and the preview sizes itself to the column it is in.
                .readableColumn()
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The same `?` the session page's cards carry, following the switcher: a
                // rider on the card tab is asking about cards, one on the recording tab is
                // asking what leaves the phone. Both are topics nobody would ever go
                // looking for in the Help index, because you only wonder once you are here.
                // On the left, so Done stays the rightmost control in the sheet.
                ToolbarItem(placement: .topBarLeading) {
                    HelpButton(topic: payload == .fit ? .shareFit : .shareCard,
                               size: .body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // The drafts are the row's, until the rider changes them. Seeded here rather than
            // in the property initializers because `row` is not available there.
            //
            // The title opens *filled in* with whatever the session is called right now —
            // his own name if he has given one, the derived one otherwise — because renaming
            // a session is nearly always editing its name rather than replacing it, and the
            // placeholder this used to rely on disappears the moment a rider touches the
            // field. `committedTitle` is seeded with the same string, so a sheet that is
            // opened and closed writes nothing: only a keystroke is a rename.
            .onAppear {
                titleDraft = SessionNaming.titleDraft(custom: row.customTitle,
                                                      derived: SessionDisplay.derivedTitle(row))
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
            .task(id: mapKey) { await loadMap() }
            // The scrub is a full FIT rewrite, so it runs off the main actor and only for
            // the tab that needs it — opening the sheet on the card must not pay for it.
            .task(id: fitKey) { await prepareFIT() }
            #if DEBUG && targetEnvironment(simulator)
            // Screenshot hooks, same family as `UI_SHEET=share` that opened this sheet:
            // `simctl` can neither flip the switcher nor pick an aspect.
            .task {
                let environment = ProcessInfo.processInfo.environment
                if environment["UI_SHARE"] == "fit" { payload = .fit }
                // `UI_SHARE=developer` raises the analysis sheet over the composer: the row
                // that opens it is a tap `simctl` cannot make, and the sheet is a beta door
                // so the hook is behind the same flag the row is.
                #if BETA
                if environment["UI_SHARE"] == "developer" { showSendToDeveloper = true }
                #endif
                if let raw = environment["UI_SHAPE"],
                   let wanted = ShareCardStats.Shape(rawValue: raw) { design.shape = wanted }
                // `UI_HERO=clean|max2s|tacks` photographs another hero without writing
                // the rider's stored choice, which a tap on the picker would.
                if let raw = environment["UI_HERO"],
                   let wanted = ShareCardStats.Hero(rawValue: raw) { design.hero = wanted }
                // `UI_MAP=1|0` photographs the card with and without the ground under it
                // without writing the rider's stored choice, which a tap on the picker would.
                if let raw = environment["UI_MAP"] { design.background = raw == "1" ? .map : .dark }
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
            // The card is a portrait picture with a share button under it. In the system's
            // 570 × 640 form sheet the button was below the fold on every aspect, so the one
            // thing the sheet exists to do could not be seen — `.page` gives it the room the
            // `.large` detent gives it on a phone.
            .presentationSizing(.page)
        }
    }

    #if BETA
    /// The row that opens `SendToDeveloperSheet`. One line under it, because the row's own
    /// label says what it does and the line says what it is *for* — a number that looks
    /// wrong, which is the only reason a rider taps it.
    @ViewBuilder
    private var sendToDeveloperRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { showSendToDeveloper = true } label: {
                Label(AppShellCopy.Share.sendToUs,
                      systemImage: "text.bubble.badge.clock")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Text(AppShellCopy.Share.sendToUsLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .sheet(isPresented: $showSendToDeveloper) {
            SendToDeveloperSheet(row: row, detail: detail)
        }
    }
    #endif

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
    /// **The title field opens filled in, not empty.** It carries the session's current name
    /// as editable text (`SessionNaming.titleDraft`), because a rider naming an afternoon is
    /// nearly always *editing* what it is already called — adding "— first 20 kn" to the spot —
    /// and a field that starts blank makes him retype the spot first. The derived name stays on
    /// as the placeholder for the one moment it is now visible: after he selects all and
    /// deletes.
    ///
    /// Empty means the derived name and no caption. Nothing here can leave the session
    /// nameless: clearing the title puts the recording's own name straight back on the card.
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
                Text("Names the session. The list, the card, the clip and the shared file "
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
        // A draft that still reads exactly like the derived name is **not** a rename — it is
        // the prefill, untouched — so it is written through as "" and the session stays
        // derived. Without this, typing a caption on a session nobody had renamed would
        // silently give it a custom title identical to the name it already showed. Clearing
        // the field says the same thing and takes the same path.
        let rename = title == SessionDisplay.derivedTitle(row) ? "" : title
        Task { @MainActor in
            await store.renameSession(row, to: rename)
            await store.setShareNote(row, to: note)
        }
    }

    // MARK: - The card

    @ViewBuilder
    private var cardSection: some View {
        ShareCardPreview(card: card, design: design)
            .padding(.top, 4)

        // Shape, the big number (layout B v2, Jan, 26 Sep 2026) and what is behind the
        // numbers: the same three decisions the period card asks (`ShareCardDesignControls`).
        // The map is offered only once the session's geometry is in memory — the sheet can
        // open before the detail has loaded, and the segment appears a moment later.
        ShareCardDesignControls(
            design: design, story: stats.story, mapOffered: mapSource != nil,
            mapNote: ShareCardDesignControls.mapNoteTrack)

        ShareCardExportRow(design: design, title: stats.title, subject: cardSubject,
                           message: cardCaption,
                           onShare: { Usage.record(.shareCard, detail: cardVariant) })

        // The other thing a rider makes to show somebody. It sits under the card rather
        // than beside it as a third `Payload` tab, because it is the same picture of the
        // same afternoon in motion — and because the card is what most riders want, and a
        // segmented control that made them choose first would put a decision in front of
        // the thing they came for.
        //
        // BETA (docs/channels.md). The replay clip with the rider's own music — the other
        // film this app makes, and the older one — is in every channel; it is this one, the
        // rendered session video, that is still proving itself.
        #if BETA
        if let detail, detail.timeRange != nil {
            Button { showReel = true } label: {
                Label("Export video", systemImage: "film")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .sheet(isPresented: $showReel) {
                ReelExportSheet(detail: detail, title: displayTitle)
            }
        }
        #endif
    }

    // MARK: - The recording

    @ViewBuilder
    private var fitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Scrubbed before it leaves", systemImage: "person.crop.circle.badge.xmark")
                .font(.subheadline.weight(.semibold))
            Text("The copy you send carries the track, the speeds, the heart rate and "
                 + "every lap. It leaves out the watch serial number and the "
                 + "paired-accessory name.\n\n"
                 + "It leaves out your rider profile too, so no name, no weight, no "
                 + "height. The original in your library is never touched.")
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
            .simultaneousGesture(TapGesture().onEnded {
                Usage.record(.fitShare, detail: includeAccelerometer ? "with wrist" : "plain")
            })
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

    /// The card's own message: the afternoon in one sentence, ending in the offer.
    ///
    /// It used to be `ShareText.cardMessage` — place, date, "CleanJibe session ·
    /// cleanjibe.org" — which says who made the picture and nothing about what is in it. The
    /// numbers are there in the pixels, but the pixels are exactly what a notification, a
    /// reply quote or a screen reader does not have (Jan, item 8, 14 Sep 2026). The web's
    /// card has said the numbers for a while; this is the same sentence, from the same
    /// formatter (`ShareCaption`), so the two platforms cannot drift.
    ///
    /// The two numbers are read off the **row**, not off `stats`: the card's cells are
    /// formatted strings chosen by a preset, and a rider who picked `lean` would otherwise
    /// get a different sentence for the same session.
    private var cardCaption: String {
        // The session's story leads (the line over the block, `SessionStory`); the
        // facts and the offer follow.
        ShareCaption.line(story: story?.line, title: displayTitle, dateLine: stats.dateLine,
                          foilPct: row.foilPct, cleanJibes: cleanJibes)
    }

    /// The subject, where the share sheet has one. The facts, without the offer.
    private var cardSubject: String {
        ShareCaption.subject(title: displayTitle, dateLine: stats.dateLine)
    }

    /// The clean-jibe count, or nil when no jibes were measured at all.
    ///
    /// The same gate the tally uses and the web's caption uses: a session whose wind axis
    /// named no jibes has no clean ones to report, and "0 clean jibes" would be a verdict
    /// nobody reached.
    private var cleanJibes: Int? {
        guard let jibes = row.jibes, jibes > 0 else { return nil }
        return row.jibesSuccessful
    }

    private var renderKey: String {
        let parts = [thumbnail == nil ? "0" : "1",
                     metrics == nil ? "0" : "1"].joined(separator: "|")
        return design.renderKey + "|" + parts + "|" + store.speedRecordPolicy.rawValue
            + "|" + displayTitle + "|" + noteDraft
    }

    /// Everything one snapshot depends on: whether it is wanted, the aspect it has to fill,
    /// the ground the rider chose for every other map in the app, whether the geometry has
    /// finished loading, and the rectangle the layout gave the track.
    ///
    /// The box is rounded to whole points on purpose. It is measured from a *scaled* preview,
    /// so a sub-point wobble as the sheet resizes would otherwise re-run the snapshotter for a
    /// framing no eye could tell from the last one.
    private var mapKey: String {
        let wanted = String(design.wantsMap(offered: mapSource != nil))
        let source = mapSource == nil ? "0" : "1"
        return wanted + "|" + design.shape.rawValue + "|" + store.mapStyle.rawValue
            + "|" + source + "|" + String(describing: design.trackBox.integral)
    }

    /// Which tab is showing (so the scrub is never paid for on the card), whether the
    /// high-rate stream stays in — and the title, because it is the file's *name*: a rider who
    /// renames the session and then shares the recording must not send it under the old one.
    private var fitKey: String {
        "\(payload.rawValue)|\(includeAccelerometer)|\(committedTitle)"
    }

    // MARK: - Work

    private func render() {
        if !design.render(card) && !countedCard {
            // A card that would not draw is the share card failing, once per visit.
            countedCard = true
            Usage.failed(.shareCard, reason: "card did not render")
        }
    }

    /// "portrait · lean · map": the share card's variant, as the usage report counts it.
    private var cardVariant: String { design.variant(mapOffered: mapSource != nil) }

    private func prepareFIT() async {
        guard payload == .fit else { return }
        fitFile = nil
        fitFailure = nil
        do {
            fitFile = try await store.shareableFIT(for: row, title: displayTitle,
                                                   includeAccelerometer: includeAccelerometer)
        } catch {
            Usage.failed(.fitShare, error: error)
            fitFailure = "This recording cannot be shared: " + String(describing: error)
        }
    }

    /// The snapshot, when it is wanted and everything it needs is to hand.
    ///
    /// A failure of any kind — no geometry, no layout yet, a snapshotter that could not reach
    /// Apple's servers — leaves `map` nil, which is the plain card. Nothing is said about it:
    /// the rider asked for a background, not for a report on one, and the card he is looking
    /// at is still the card he can send.
    private func loadMap() async {
        // Only while the map is the background: a rider whose background is a shot of his
        // own must not pay for a snapshot nothing will ever show.
        guard design.wantsMap(offered: mapSource != nil), let source = mapSource,
              design.trackBox.width > 1 else {
            design.map = nil
            return
        }
        design.map = await ShareCardMapper.make(source: source, size: card.size,
                                                trackBox: design.trackBox,
                                                style: store.mapStyle)
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
        let thinned = shareCoordinates
        guard thinned.count >= 2 else {
            return TrackThumbnail(points: [], speed: [], maxKn: 0)
        }
        return TrackThumbnail(
            points: TrackThumbnail.outline(coordinates: thinned),
            marks: shareMarks(thinned),
            // The extent the normalization threw away, kept — this outline is built the same
            // way the cached ones are, so it carries the same thing they now carry.
            bounds: TrackThumbnail.Projection(
                thinned.map { (lat: $0.lat, lon: $0.lon) })?.bounds,
            speed: [], maxKn: maxSpeedKn)
    }

    /// The same polyline, thinned the same way, **before** it is normalized into a unit box.
    ///
    /// Split out because the card's optional map background needs the degrees back: a
    /// snapshot has to be framed on the earth, and the outline above has thrown the earth
    /// away by design. One thinning, two readers, so the mapped track and the plain one are
    /// the same vertices.
    var shareCoordinates: [(lat: Double, lon: Double, flying: Bool)] {
        var coordinates: [(lat: Double, lon: Double, flying: Bool)] = []
        for segment in segments {
            for point in segment.points {
                coordinates.append((point.lat, point.lon, segment.flying))
            }
        }
        guard coordinates.count >= 2 else { return [] }
        let budget = TrackThumbnail.maxPoints * 2      // a card can carry more than a row
        let stride = max(1, (coordinates.count + budget - 1) / budget)
        var thinned: [(lat: Double, lon: Double, flying: Bool)] = []
        for (index, point) in coordinates.enumerated() {
            let phaseChange = thinned.last.map { $0.flying != point.flying } ?? true
            if index % stride == 0 || index == coordinates.count - 1 || phaseChange {
                thinned.append(point)
            }
        }
        return thinned
    }

    /// What the map background is drawn from: the thinned polyline and the same two marker
    /// collections `shareMarks` normalizes, still in degrees. Nil when there is no track.
    var shareGeography: ShareCardMapSource? {
        let thinned = shareCoordinates
        guard thinned.count >= 2 else { return nil }
        var marks = turnPins.map { pin -> ShareCardMapSource.Mark in
            let kind: TrackThumbnail.Mark.Kind
            switch pin.outcome {
            case .fellIn: kind = .fellIn
            case .touchdown: kind = .touchdown
            case .flewThrough: kind = .flewThrough
            }
            return ShareCardMapSource.Mark(lat: pin.lat, lon: pin.lon, kind: kind)
        }
        marks.append(contentsOf: splashMarks.map {
            ShareCardMapSource.Mark(lat: $0.lat, lon: $0.lon, kind: .splash)
        })
        return ShareCardMapSource(
            points: thinned.map {
                ShareCardMapSource.Point(lat: $0.lat, lon: $0.lon, flying: $0.flying)
            },
            marks: marks)
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
