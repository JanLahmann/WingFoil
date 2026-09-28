import SwiftUI
import WingFoilKit

/// How a period card draws its afternoons (Jan, 28 Sep 2026).
enum PeriodCardTracks: String, CaseIterable, Identifiable {
    /// Every outline on one another, at one scale (`TrackStack`) — the card this was first.
    case all
    /// One afternoon of the period, drawn big, like a session card.
    case one
    /// Each afternoon's own small track in a grid (`TrackCollage`).
    case collage

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: AppShellCopy.Share.allSessions
        case .one: AppShellCopy.Share.oneSession
        case .collage: AppShellCopy.Share.collage
        }
    }
}

/// The **period card** composer — the session card's sheet, with a week on it.
///
/// Everything a card is designed with is the session composer's, shared rather than copied
/// (`ShareCardDesign`): the three shapes, layout B v2 with its hero picker, the background —
/// dark, map or a photo of the rider's — the live preview, an `ImageRenderer` at 3× and a
/// `ShareLink` handing the PNG straight to the share sheet with nothing uploaded. What is the
/// period's own:
///
/// * the numbers are the aggregate block and its story facts (`ShareCardStats.make(period:)`),
///   not a session's key-metrics block, and the third hero is the session count;
/// * the artwork is a choice of three (`PeriodCardTracks`): every outline stacked, one
///   session drawn big, or a collage of them;
/// * the map is offered where there is one ground to frame — the stack only where the period
///   is one place (`Period.mapGround`: a month split between two lakes has a union box that is
///   mostly the road between them), one session wherever it has a track, the collage never;
/// * the title and the caption are for this card only: a period is not a row in the library.
struct PeriodShareView: View {
    let period: Period

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var store
    @Environment(ThumbnailStore.self) private var thumbnails

    @State private var design = ShareCardDesign()
    @State private var tracks = PeriodCardTracks.all
    /// The session "One session" draws. Seeded with the newest once the rows are in.
    @State private var chosenId: String?
    @State private var titleDraft = ""
    @State private var noteDraft = ""
    /// The period's rows, oldest first, for the session picker's names.
    @State private var rows: [SessionRow] = []
    /// Every outline that has arrived, by session id.
    @State private var outlines: [String: TrackThumbnail] = [:]

    private var stats: ShareCardStats {
        ShareCardStats.make(period: period, hero: design.hero,
                            title: SessionNaming.customTitle(titleDraft),
                            note: noteDraft)
    }

    /// The outlines in the period's own order, oldest first.
    private var ordered: [TrackThumbnail] {
        period.sessionIds.compactMap { outlines[$0] }
    }

    private var chosen: TrackThumbnail? {
        chosenId.flatMap { outlines[$0] }
    }

    /// What the chosen artwork can be put on the earth with, if anything.
    private var mapSources: [ShareCardMapSource] {
        switch tracks {
        case .all:
            period.mapGround ? ordered.compactMap(ShareCardMapSource.init(thumbnail:)) : []
        case .one:
            chosen.flatMap(ShareCardMapSource.init(thumbnail:)).map { [$0] } ?? []
        case .collage:
            []
        }
    }

    private var mapOffered: Bool { !mapSources.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ShareCardPreview(card: card, design: design)
                    naming
                    tracksPicker
                    ShareCardDesignControls(
                        design: design, story: stats.story, mapOffered: mapOffered,
                        mapNote: tracks == .one ? ShareCardDesignControls.mapNoteTrack
                                                : ShareCardDesignControls.mapNoteStack)
                    ShareCardExportRow(design: design, title: stats.title,
                                       subject: stats.title,
                                       onShare: {
                                           Usage.record(.periodShare,
                                                        detail: design.variant(
                                                            mapOffered: mapOffered)
                                                            + " · " + tracks.rawValue)
                                       })
                }
                .padding()
                .readableColumn()
            }
            .navigationTitle("Share this period")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HelpButton(topic: .shareCard, size: .body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                titleDraft = period.title
                // `UI_SHAPE` / `UI_HERO` / `UI_MAP` / `UI_TRACKS` photograph another card
                // without writing the rider's stored choices — the session composer's hooks.
                let environment = ProcessInfo.processInfo.environment
                if let raw = environment["UI_SHAPE"],
                   let wanted = ShareCardStats.Shape(rawValue: raw) { design.shape = wanted }
                if let raw = environment["UI_HERO"],
                   let wanted = ShareCardStats.Hero(rawValue: raw) { design.hero = wanted }
                if let raw = environment["UI_MAP"] { design.background = raw == "1" ? .map : .dark }
                if let raw = environment["UI_TRACKS"],
                   let wanted = PeriodCardTracks(rawValue: raw) { tracks = wanted }
            }
            .task(id: period.key) { await loadOutlines() }
            .task(id: mapKey) { await loadMap() }
            .task(id: renderKey) { design.render(card) }
            // The session composer's trade, for the same reason: a card preview and an
            // export button do not fit the system's form sheet.
            .presentationSizing(.page)
        }
    }

    // MARK: - The card

    /// Typed rather than `some View`, so `loadMap` can ask it for the size the snapshot has to
    /// fill — the same shape `ShareComposerView.card` is written in, and for the same reason.
    private var card: ShareCardView {
        let photo = design.cardPhoto
        let map = photo == nil && mapOffered ? design.map : nil
        let report: (CGRect) -> Void = { [design] in design.trackBox = $0 }
        switch tracks {
        case .all:
            return ShareCardView(stats: stats, shape: design.shape, thumbnails: ordered,
                                 photo: photo, map: map, onTrackFrame: report)
        case .one:
            return ShareCardView(stats: stats, shape: design.shape, thumbnail: chosen,
                                 photo: photo, map: map, onTrackFrame: report)
        case .collage:
            return ShareCardView(stats: stats, shape: design.shape,
                                 collage: TrackCollage.pick(ordered), photo: photo,
                                 onTrackFrame: report)
        }
    }

    @ViewBuilder
    private var naming: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The same two fields the session composer draws, and the same chrome: these
            // sit in a plain `ScrollView`, where `.roundedBorder` is black on black in dark
            // mode for exactly the reason the key field was (`AppTextFieldChrome`).
            TextField("Title", text: $titleDraft)
                .appTextFieldChrome()
                .onChange(of: titleDraft) {
                    titleDraft = String(titleDraft.prefix(SessionNaming.titleLimit))
                }
            // Optional, like the title above it: an empty field simply leaves the line off.
            TextField("A line of your own", text: $noteDraft)
                .appTextFieldChrome()
                .onChange(of: noteDraft) {
                    noteDraft = String(noteDraft.prefix(SessionNaming.noteLimit))
                }
            // Transient, unlike a session's: a period is not a row in the library, so there
            // is nothing to rename and nothing to store the caption on. The two fields feed
            // this render and are gone when the sheet closes.
            Text("The title and the caption are for this card only. A period has no "
                 + "record in the library to rename.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// All sessions, one session, or a collage — and, for one, which. Not offered for a period
    /// of one afternoon, where the three would be the same picture.
    @ViewBuilder
    private var tracksPicker: some View {
        if period.sessions > 1 {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppShellCopy.Share.tracks)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker(AppShellCopy.Share.tracks, selection: $tracks) {
                    ForEach(PeriodCardTracks.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                switch tracks {
                case .one:
                    Picker(AppShellCopy.Share.oneSession, selection: $chosenId) {
                        // Newest first: the afternoon a rider wants on a card is usually
                        // the one he just rode.
                        ForEach(rows.reversed(), id: \.id) { row in
                            Text(SessionDisplay.title(row) + " · "
                                 + Fmt.shortDate(row.startDate, zone: row.displayZone))
                                .tag(Optional(row.id))
                        }
                    }
                    .pickerStyle(.menu)
                case .collage:
                    Text(AppShellCopy.fill(AppShellCopy.Share.collageNote,
                                           ["limit": String(TrackCollage.limit)]))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .all:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Work

    private var renderKey: String {
        [design.renderKey, titleDraft, noteDraft, String(outlines.count), tracks.rawValue,
         chosenId ?? "-", String(mapOffered)].joined(separator: "|")
    }

    /// Everything one snapshot depends on: whether it is wanted and offered, the artwork, the
    /// aspect it has to fill, the ground the rider chose for every other map in the app, how
    /// many outlines have arrived, and the rectangle the layout gave them — rounded to whole
    /// points, because it is measured from a scaled preview.
    private var mapKey: String {
        [String(design.wantsMap(offered: mapOffered)), tracks.rawValue, chosenId ?? "-",
         design.shape.rawValue, store.mapStyle.rawValue, String(outlines.count),
         String(describing: design.trackBox.integral)].joined(separator: "|")
    }

    /// One snapshot, framed on the union of the artwork's outlines. Every failure leaves the
    /// map nil, which is the plain card — the rider asked for a background, not a report.
    private func loadMap() async {
        let sources = mapSources
        guard design.wantsMap(offered: !sources.isEmpty), design.trackBox.width > 1 else {
            design.map = nil
            return
        }
        design.map = tracks == .one
            ? await ShareCardMapper.make(sources: sources, size: card.size,
                                         trackBox: design.trackBox, style: store.mapStyle)
            : await ShareCardMapper.makeStack(sources: sources, size: card.size,
                                              trackBox: design.trackBox,
                                              style: store.mapStyle)
    }

    /// The period's outlines, from the same cache the library rows read.
    ///
    /// A thumbnail costs one FIT parse and is kept for ever, so a period the rider has
    /// scrolled past is free; one he has not is a short wait while the sheet already shows its
    /// numbers. A session whose thumbnail cannot be built is simply not on the card — a card
    /// with eleven of twelve afternoons on it is a card.
    private func loadOutlines() async {
        let all = (try? await store.library.sessions()) ?? []
        let wanted = Set(period.sessionIds)
        let order = Dictionary(uniqueKeysWithValues: period.sessionIds.enumerated()
            .map { ($1, $0) })
        rows = all.filter { wanted.contains($0.id) }
            .sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        if chosenId == nil { chosenId = rows.last?.id }
        for row in rows { thumbnails.request(row) }
        // Poll the cache rather than plumb a callback through: the store is `@Observable`
        // and this is a sheet that is open for seconds, not a list that scrolls.
        for _ in 0..<40 {
            var found: [String: TrackThumbnail] = [:]
            for id in period.sessionIds {
                if let thumbnail = thumbnails.thumbnail(for: id) { found[id] = thumbnail }
            }
            if found.count != outlines.count { outlines = found }
            if found.count == rows.count { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }
}
