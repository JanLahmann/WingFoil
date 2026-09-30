import PhotosUI
import SwiftUI
import WingFoilKit

/// What sits behind the card's words — the same three on the session card and the period card
/// (Jan, 28 Sep 2026): the dark brand card, the map under the track, or a photo of the rider's.
enum ShareCardBackground: String, CaseIterable, Identifiable {
    case dark, map, photo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: AppShellCopy.Share.dark
        case .map: AppShellCopy.Share.map
        case .photo: AppShellCopy.Share.photo
        }
    }
}

/// **Everything the two card composers share**, held once: the shape, the big number, the
/// background and its photo, the map snapshot, the measured track box, and the rendered PNG.
///
/// The session composer (`ShareComposerView`) and the period composer (`PeriodShareView`)
/// differ only in their *data* — which numbers, which artwork, which ground the map can be
/// framed on, and what a title edit means. Every control that is not about the data lives here
/// and in the three views below it, so a change to how a card is designed is a change to both
/// cards at once.
///
/// The shape, the hero and the map habit are device preferences (`ShareCardHeroStore`,
/// `ShareCardMapStore`), written only on a tap — the screenshot hooks set the same state
/// without writing it. A photo is never remembered: it is one afternoon's picture.
@MainActor @Observable
final class ShareCardDesign {
    var shape = ShareCardStats.Shape.portrait
    var hero = ShareCardHeroStore.load(from: .standard)
    /// What the rider asked for. The card uses `effectiveBackground`, which falls back to dark
    /// where the choice cannot be honoured (no ground to frame, no photo yet).
    var background: ShareCardBackground =
        ShareCardMapStore.load(from: .standard) ? .map : .dark
    var pickedItem: PhotosPickerItem?
    var photo: Image?
    var photoFailed = false
    /// The system photo picker, raised by the Photo segment when there is no photo yet.
    var showsPhotoPicker = false
    /// The snapshot and the track projected onto it, once it has arrived.
    var map: ShareCardMap?
    /// Where the card's own layout put the track, reported by the preview — see
    /// `ShareCardView.onTrackFrame` and `ShareCardMap` for why it is measured.
    var trackBox: CGRect = .zero
    var rendered: Image?
    /// The same picture as bytes, for the one reader that needs them (the feedback mail).
    var renderedImage: UIImage?
    /// Width the sheet has for the preview; 0 until the first layout pass.
    var availableWidth: CGFloat = 0

    /// Whether a map is wanted **and** the card can carry one right now.
    func wantsMap(offered: Bool) -> Bool { background == .map && offered }

    /// The photo behind the card, only while the Photo background is the one chosen.
    var cardPhoto: Image? { background == .photo ? photo : nil }

    /// The background the card is actually drawn with.
    func effectiveBackground(mapOffered: Bool) -> ShareCardBackground {
        switch background {
        case .map: mapOffered ? .map : .dark
        case .photo: photo == nil ? .dark : .photo
        case .dark: .dark
        }
    }

    /// A tap on the background picker. Map and dark are the rider's habit and are written
    /// back; Photo without a photo opens the picker and waits for one.
    func choose(_ next: ShareCardBackground) {
        switch next {
        case .photo:
            if photo == nil {
                showsPhotoPicker = true
            } else {
                background = .photo
            }
        case .map, .dark:
            background = next
            ShareCardMapStore.save(next == .map, to: .standard)
        }
    }

    func chooseHero(_ chosen: ShareCardStats.Hero) {
        hero = chosen
        ShareCardHeroStore.save(chosen, to: .standard)
    }

    func loadPhoto() async {
        guard let pickedItem else { return }
        photoFailed = false
        guard let data = try? await pickedItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            photoFailed = true
            return
        }
        photo = Image(uiImage: image)
        background = .photo
    }

    func removePhoto() {
        photo = nil
        pickedItem = nil
        background = ShareCardMapStore.load(from: .standard) ? .map : .dark
    }

    /// Render the card at its export scale. False when `ImageRenderer` produced nothing.
    @discardableResult
    func render(_ card: ShareCardView) -> Bool {
        let renderer = ImageRenderer(content: card)
        renderer.scale = ShareCardView.renderScale
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { return false }
        rendered = Image(uiImage: image)
        renderedImage = image
        return true
    }

    /// "portrait · clean · map": the variant the usage report counts.
    func variant(mapOffered: Bool) -> String {
        let ground = cardPhoto != nil ? "photo" : (map != nil ? "map" : "plain")
        return shape.rawValue + " · " + hero.rawValue + " · " + ground
    }

    /// What every render depends on that this object holds. Each composer adds its own data.
    var renderKey: String {
        [shape.rawValue, hero.rawValue, cardPhoto == nil ? "plain" : "photo",
         map == nil ? "0" : "1"].joined(separator: "|")
    }
}

/// The card at whatever size the sheet has room for — the live view, scaled.
///
/// `ShareCardView` lays itself out at a fixed size (its export size over `renderScale`), so a
/// shape wider than the phone is scaled down for the preview rather than reflowed: a card that
/// reflowed to fit the sheet would not be the card that gets exported. It is also the view that
/// measures the track box the map snapshot is framed against.
struct ShareCardPreview: View {
    let card: ShareCardView
    @Bindable var design: ShareCardDesign

    var body: some View {
        let scale = design.availableWidth > 0
            ? min(1, design.availableWidth / card.size.width) : 1
        card
            .clipShape(.rect(cornerRadius: 18))
            .shadow(radius: 10, y: 4)
            .scaleEffect(scale)
            .frame(width: card.size.width * scale, height: card.size.height * scale)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                design.availableWidth = $0
            }
    }
}

/// Shape, big number and background — the three decisions every card asks, in that order.
///
/// **The hero picker** offers only the heroes this card can carry, and with one left there is
/// nothing to choose. **The background** offers the map only where the card can be put on the
/// earth (`mapOffered`): a switch that is there and does nothing is worse than one that is not.
struct ShareCardDesignControls: View {
    @Bindable var design: ShareCardDesign
    let story: ShareCardStats.Story?
    let mapOffered: Bool
    /// The line under the picker while the map is the background.
    let mapNote: String

    /// The two lines `mapNote` is, one home each: one track on the ground, or a stack.
    static let mapNoteTrack =
        "Draws the track over the map, on the ground you picked for the session map. "
        + "Needs a connection. Without one the card comes out plain."
    static let mapNoteStack =
        "Draws every outline over the map, on the ground you picked for the session map. "
        + "Needs a connection. Without one the card comes out plain."

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Shape", selection: $design.shape) {
                ForEach(ShareCardStats.Shape.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            // The binding writes the preference itself, so only a *tap* is remembered.
            if let options = story?.heroOptions, options.count > 1 {
                Picker(PresentationCopy.card("optionTitle"),
                       selection: Binding(get: { story?.hero?.kind ?? design.hero },
                                          set: { design.chooseHero($0) })) {
                    ForEach(options) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            backgroundPicker
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .photosPicker(isPresented: $design.showsPhotoPicker, selection: $design.pickedItem,
                      matching: .images, photoLibrary: .shared())
        .task(id: design.pickedItem) { await design.loadPhoto() }
    }

    private var offered: [ShareCardBackground] {
        ShareCardBackground.allCases.filter { $0 != .map || mapOffered }
    }

    @ViewBuilder
    private var backgroundPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppShellCopy.Share.background)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.readableSecondary)
            Picker(AppShellCopy.Share.background,
                   selection: Binding(get: { design.effectiveBackground(mapOffered: mapOffered) },
                                      set: { design.choose($0) })) {
                ForEach(offered) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            switch design.effectiveBackground(mapOffered: mapOffered) {
            case .map:
                note(mapNote)
            case .photo:
                HStack(spacing: 12) {
                    photoPicker
                    Button(role: .destructive) { design.removePhoto() } label: {
                        Label("Remove", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                }
            case .dark:
                EmptyView()
            }
            if design.photoFailed {
                Text("That image could not be read.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Another shot, once a photo is the background. `PhotosPicker` runs out of process, so
    /// there is no photo-library prompt and the app sees only the picture handed to it.
    private var photoPicker: some View {
        PhotosPicker(selection: $design.pickedItem, matching: .images,
                     photoLibrary: .shared()) {
            Label("Change photo", systemImage: "photo")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.readableSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The share button and the line under it: the rendered PNG straight into the share sheet,
/// nothing uploaded. `message` is the session card's caption; a period card has none.
struct ShareCardExportRow: View {
    @Bindable var design: ShareCardDesign
    let title: String
    let subject: String
    var message: String?
    let onShare: () -> Void

    var body: some View {
        if let rendered = design.rendered {
            Group {
                if let message {
                    ShareLink(item: rendered, subject: Text(subject), message: Text(message),
                              preview: SharePreview(title, image: rendered)) { label }
                } else {
                    ShareLink(item: rendered, subject: Text(subject),
                              preview: SharePreview(title, image: rendered)) { label }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            // Counted at the tap, which is the rider sharing a card that exists. What the
            // share sheet does next is Apple's, and it reports nothing back.
            .simultaneousGesture(TapGesture().onEnded { onShare() })
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 44)
        }

        Text("The card is rendered at " + String(Int(design.shape.size.width)) + " × "
             + String(Int(design.shape.size.height))
             + " px. " + Copy.straightToTheShareSheet)
            .font(.caption2)
            .foregroundStyle(.readableSecondary)
            .multilineTextAlignment(.center)
    }

    private var label: some View {
        Label("Share card", systemImage: "square.and.arrow.up")
            .frame(maxWidth: .infinity)
    }
}
