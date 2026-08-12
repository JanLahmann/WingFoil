import PhotosUI
import SwiftUI
import WingFoilKit

/// Builds a shareable image of one session: pick an aspect, optionally drop one of your
/// own photos behind it, export.
///
/// `PhotosPicker` runs out of process, so there is no photo-library permission prompt and
/// the app never gains access to anything the rider did not hand it. The picked image is
/// held in memory for the render and nothing is written anywhere until the share sheet
/// exports it.
struct ShareComposerView: View {
    let row: SessionRow
    /// The already-loaded detail, when the screen has it: the card's outline then comes
    /// from geometry that is in memory rather than from a second FIT parse.
    var detail: SessionDetail?

    @Environment(\.dismiss) private var dismiss
    @Environment(ThumbnailStore.self) private var thumbnails

    @State private var shape = ShareCardStats.Shape.portrait
    @State private var pickedItem: PhotosPickerItem?
    @State private var photo: Image?
    @State private var photoFailed = false
    @State private var rendered: Image?

    private var stats: ShareCardStats {
        ShareCardStats.make(row: row, title: SessionDisplay.title(row))
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
                    card
                        .clipShape(.rect(cornerRadius: 18))
                        .shadow(radius: 10, y: 4)
                        .padding(.top, 4)

                    Picker("Shape", selection: $shape) {
                        ForEach(ShareCardStats.Shape.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    photoControls

                    if let rendered {
                        ShareLink(item: rendered,
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
                .padding(.horizontal)
                .padding(.bottom, 28)
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Re-render whenever anything visible changes. `ImageRenderer` is main-actor
            // work, but a card is a handful of shapes and some text — cheap enough to redo
            // on a shape flip rather than caching two of them.
            .task(id: renderKey) { render() }
            .task(id: pickedItem) { await loadPhoto() }
        }
    }

    private var renderKey: String {
        "\(shape.rawValue)|\(photo == nil ? "plain" : "photo")|\(thumbnail == nil ? 0 : 1)"
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

    /// The card's track outline, built from the segments already in memory.
    ///
    /// Same normalization as the cached list thumbnails (`TrackThumbnail.outline`), so a
    /// session looks like itself in the list and on the card. The map series is thinned for
    /// MapKit (up to 6 000 vertices); a card at 1080 px wide cannot show more than a few
    /// hundred, so it is thinned again here.
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
                              speed: [], maxKn: maxSpeedKn)
    }
}
