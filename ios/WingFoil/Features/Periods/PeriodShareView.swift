import SwiftUI
import WingFoilKit

/// The **period card** composer — the session card's sheet, with a week on it.
///
/// Everything here is the session composer's contract unchanged: three shapes, two presets,
/// the rider's own title and one caption, an `ImageRenderer` at 3× and a `ShareLink` handing
/// the PNG straight to the share sheet with nothing uploaded. What differs is what is being
/// described, and therefore two things:
///
/// * the stats are the aggregate block (`ShareCardStats.make(period:)`), not a session's
///   key-metrics block;
/// * the artwork is every session's outline stacked, because a period has no single ride and
///   picking one would be picking a favourite;
/// * the map background is offered only where the period **has** one ground — every afternoon
///   inside a single 3 km cluster (`Period.mapGround`). A month split between two lakes has a
///   union bounding box that is mostly the road between them, so the switch is not there at
///   all rather than there and useless.
///
/// There is no photo picker and no FIT tab: a period is not a file, and a rider's own
/// photograph is a picture of one afternoon.
struct PeriodShareView: View {
    let period: Period

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var store
    @Environment(ThumbnailStore.self) private var thumbnails

    @State private var shape = ShareCardStats.Shape.portrait
    /// Seeded from the last card the rider exported, and written back — the preset is a
    /// preference about cards, not about this period, and it is the same preference the
    /// session card reads.
    @State private var preset = ShareCardPresetStore.load(from: .standard)
    /// And so is the map switch: `wingfoil.shareCard.map.v1`, one habit per device, read and
    /// written by both composers. Honoured only where this period can offer a ground.
    @State private var wantsMap = ShareCardMapStore.load(from: .standard)
    @State private var titleDraft = ""
    @State private var noteDraft = ""
    @State private var outlines: [TrackThumbnail] = []
    @State private var map: ShareCardMap?
    /// The rectangle the layout gave the stack, measured from the live view — see
    /// `ShareCardView.onTrackFrame`, and `ShareCardMap` for why it is measured rather than
    /// recomputed.
    @State private var trackBox: CGRect = .zero
    @State private var rendered: Image?

    /// Whether this period can carry a ground at all. Decided in the kit (`LibraryStore`) and
    /// in the analyzer (`library._map_ground`) from the same rule, never here.
    private var offersMap: Bool { period.mapGround }

    private var stats: ShareCardStats {
        ShareCardStats.make(period: period, preset: preset,
                            title: SessionNaming.customTitle(titleDraft),
                            note: noteDraft)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    preview
                    naming
                    pickers
                    mapToggle
                    exportRow
                }
                .padding()
            }
            .navigationTitle("Share this period")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { titleDraft = period.title }
            .task(id: period.key) { await loadOutlines() }
            .task(id: mapKey) { await loadMap() }
            .task(id: renderKey) { render() }
            .onChange(of: preset) { ShareCardPresetStore.save(preset, to: .standard) }
        }
    }

    // MARK: - The card

    /// Typed rather than `some View`, so `loadMap` can ask it for the size the snapshot has to
    /// fill — the same shape `ShareComposerView.card` is written in, and for the same reason.
    private var card: ShareCardView {
        ShareCardView(stats: stats, shape: shape, thumbnails: outlines, map: map,
                      onTrackFrame: { trackBox = $0 })
    }

    @ViewBuilder
    private var preview: some View {
        if let rendered {
            rendered
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                .clipShape(.rect(cornerRadius: 12))
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    @ViewBuilder
    private var naming: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $titleDraft)
                .textFieldStyle(.roundedBorder)
                .onChange(of: titleDraft) {
                    titleDraft = String(titleDraft.prefix(SessionNaming.titleLimit))
                }
            TextField("A line of your own (optional)", text: $noteDraft)
                .textFieldStyle(.roundedBorder)
                .onChange(of: noteDraft) {
                    noteDraft = String(noteDraft.prefix(SessionNaming.noteLimit))
                }
            // Transient, unlike a session's: a period is not a row in the library, so there
            // is nothing to rename and nothing to store the caption on. The two fields feed
            // this render and are gone when the sheet closes.
            Text("The title and the caption are for this card only — a period has no record "
                 + "in the library to rename.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var pickers: some View {
        Picker("Shape", selection: $shape) {
            ForEach(ShareCardStats.Shape.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)

        Picker("Stats", selection: $preset) {
            ForEach(ShareCardStats.Preset.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)

        Text(preset == .lean
             ? "Sessions, hours, clean jibes, CPH and max 2 s."
             : "Everything the period block shows.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// **Offered only where the period has a ground.** Not offered-and-inert: a switch that is
    /// on and does nothing is worse than a switch that is not there, and "which rectangle of
    /// the earth?" genuinely has no answer for a month spent at two lakes.
    @ViewBuilder
    private var mapToggle: some View {
        if offersMap {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(get: { wantsMap },
                                     set: { wanted in
                                         wantsMap = wanted
                                         ShareCardMapStore.save(wanted, to: .standard)
                                     })) {
                    Text("Map background")
                }
                Text("Draws every outline over the map, on the ground you picked for the "
                     + "session map. Needs a connection; without one the card comes out "
                     + "plain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var exportRow: some View {
        if let rendered {
            ShareLink(item: rendered,
                      subject: Text(stats.title),
                      preview: SharePreview(stats.title, image: rendered)) {
                Label("Share card", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        Text("Rendered at \(Int(shape.size.width)) × \(Int(shape.size.height)) px. Nothing "
             + "is uploaded — the image is handed straight to the share sheet.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Work

    private var renderKey: String {
        "\(shape.rawValue)|\(preset.rawValue)|\(titleDraft)|\(noteDraft)|\(outlines.count)"
            + "|\(map == nil ? 0 : 1)"
    }

    /// Everything one snapshot depends on: whether it is wanted and offered, the aspect it has
    /// to fill, the ground the rider chose for every other map in the app, how many outlines
    /// have arrived, and the rectangle the layout gave them.
    ///
    /// The box is rounded to whole points on purpose: it is measured from a scaled preview, so
    /// a sub-point wobble as the sheet resizes would otherwise re-run the snapshotter for a
    /// framing no eye could tell from the last one.
    private var mapKey: String {
        "\(wantsMap && offersMap)|\(shape.rawValue)|\(store.mapStyle.rawValue)"
            + "|\(outlines.count)|\(trackBox.integral)"
    }

    /// One snapshot for the whole period, framed on the union of its outlines.
    ///
    /// Every failure — the switch off, no ground to offer, no outlines yet, a snapshotter that
    /// could not reach Apple's servers — leaves `map` nil, which is the plain card. Nothing is
    /// said about it: the rider asked for a background, not for a report on one.
    private func loadMap() async {
        guard wantsMap, offersMap, trackBox.width > 1 else {
            map = nil
            return
        }
        let sources = outlines.compactMap(ShareCardMapSource.init(thumbnail:))
        guard !sources.isEmpty else {
            map = nil
            return
        }
        map = await ShareCardMapper.makeStack(sources: sources, size: card.size,
                                              trackBox: trackBox, style: store.mapStyle)
    }

    private func render() {
        let renderer = ImageRenderer(content: card)
        renderer.scale = ShareCardView.renderScale
        renderer.isOpaque = true
        if let image = renderer.uiImage { rendered = Image(uiImage: image) }
    }

    /// The period's outlines, from the same cache the library rows read.
    ///
    /// A thumbnail costs one FIT parse and is kept for ever, so a period the rider has
    /// scrolled past is free; one he has not is a short wait while the sheet already shows its
    /// numbers. A session whose thumbnail cannot be built is simply not in the stack — a card
    /// with eleven of twelve afternoons on it is a card.
    private func loadOutlines() async {
        let rows = (try? await store.library.sessions()) ?? []
        let wanted = Set(period.sessionIds)
        let mine = rows.filter { wanted.contains($0.id) }
        for row in mine { thumbnails.request(row) }
        // Poll the cache rather than plumb a callback through: the store is `@Observable`
        // and this is a sheet that is open for seconds, not a list that scrolls.
        for _ in 0..<40 {
            let found = period.sessionIds.compactMap { thumbnails.thumbnail(for: $0) }
            if found.count != outlines.count { outlines = found }
            if found.count == mine.count { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }
}
