import SwiftUI
import PhotosUI
import SkylitCore

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, CGImage>()

    func image(_ key: String) -> CGImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: CGImage, _ key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

struct FramePhoto: View {
    @Environment(\.theme) private var theme
    let store: FrameStore
    let id: String
    let maxEdge: Int
    var fills = true
    @State private var image: CGImage?
    @State private var failed = false

    private var key: String { "\(id)-\(maxEdge)" }

    var body: some View {
        ZStack {
            theme.soft.opacity(0.6)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: fills ? .fill : .fit)
                    .transition(.opacity)
            } else if failed {
                Image(systemName: "photo").foregroundStyle(theme.muted)
            } else {
                ProgressView().tint(theme.muted)
            }
        }
        .task(id: key) {
            if let cached = ThumbnailCache.shared.image(key) {
                image = cached
                return
            }
            guard let data = try? await store.photoData(id: id) else {
                failed = !Task.isCancelled
                return
            }
            let edge = maxEdge
            let decoded = await Task.detached { ImagePreparation.thumbnail(from: data, maxEdge: edge) }.value
            guard let decoded else {
                failed = true
                return
            }
            ThumbnailCache.shared.store(decoded, key)
            withAnimation(Motion.fade) { image = decoded }
        }
    }
}

struct PhotosScreen: View {
    @Environment(\.theme) private var theme
    let store: FrameStore
    let openSetup: () -> Void
    @State private var picks: [PhotosPickerItem] = []
    @State private var viewing: PhotoRef?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        Screen(title: "Photos", store: store) {
            EmptyView()
        } content: {
            Text(countLine).textStyle(.body).foregroundStyle(theme.muted)
            if let upload = store.upload {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sending photo \(upload.index + 1) of \(upload.total)").textStyle(.label).foregroundStyle(theme.ink)
                        ProgressView(value: upload.overall).tint(theme.accent)
                        Text("Keep Skylit open until this finishes.").textStyle(.caption).foregroundStyle(theme.muted)
                    }
                }
                .transition(.opacity)
            } else {
                PhotosPicker(selection: $picks, maxSelectionCount: 30, matching: .images) {
                    Label("Add photos", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            if store.state?.settings.supportsICloudAlbum == true {
                Button(action: openSetup) {
                    HStack(spacing: 12) {
                        Image(systemName: "icloud")
                            .foregroundStyle(theme.accent)
                            .frame(width: 36, height: 36)
                            .background(theme.soft, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(albumTitle).textStyle(.label).foregroundStyle(theme.ink).multilineTextAlignment(.leading)
                            Text(albumDetail).textStyle(.caption).foregroundStyle(theme.muted).multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(theme.muted)
                    }
                    .padding(14)
                    .background(theme.panel, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            if store.photos.isEmpty, store.upload == nil {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No photos sent from a phone yet").textStyle(.heading).foregroundStyle(theme.ink)
                        Text("Photos you add join the frame's slideshow. They are resized to fit the frame and sent over your Wi-Fi only.")
                            .textStyle(.caption)
                            .foregroundStyle(theme.muted)
                    }
                }
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(store.photos) { photo in
                        Button {
                            viewing = photo
                        } label: {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(FramePhoto(store: store, id: photo.id, maxEdge: 360))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Photo added \(added(photo))")
                    }
                }
            }
        }
        .animation(Motion.settle, value: store.upload == nil)
        .task(id: store.state?.photos.count) { await store.loadPhotos() }
        .onChange(of: picks) { _, selected in
            guard !selected.isEmpty else { return }
            picks = []
            Task {
                await store.uploadPhotos(count: selected.count) { index in
                    try? await selected[index].loadTransferable(type: Data.self)
                }
            }
        }
        .sheet(item: $viewing) { photo in
            PhotoViewer(store: store, photo: photo, added: added(photo)).environment(\.theme, theme)
        }
    }

    private var albumTitle: String {
        guard let album = store.state?.settings.icloudAlbum else { return "Mirror an iCloud shared album" }
        return album.name.isEmpty ? "iCloud shared album" : album.name
    }

    private var albumDetail: String {
        guard let album = store.state?.settings.icloudAlbum else { return "Set it up once in Frame and it stays in sync by itself." }
        if album.syncing { return "Syncing with iCloud" }
        if album.error != nil { return "Needs attention in Frame" }
        return album.count == 1 ? "1 picture from iCloud" : "\(album.count) pictures from iCloud"
    }

    private var countLine: String {
        let count = store.state?.photos.count ?? store.photos.count
        return count == 1 ? "1 photo on the frame" : "\(count) photos on the frame"
    }

    private func added(_ photo: PhotoRef) -> String {
        ISO8601.date(photo.addedAt)?.formatted(date: .abbreviated, time: .shortened) ?? ""
    }
}

struct PhotoViewer: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let store: FrameStore
    let photo: PhotoRef
    let added: String
    @State private var confirmsDelete = false

    var body: some View {
        SheetScaffold(title: "Photo") {
            FramePhoto(store: store, id: photo.id, maxEdge: 1600, fills: false)
                .frame(maxWidth: .infinity)
                .frame(height: 380)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            if !added.isEmpty {
                Text("Added \(added)").textStyle(.caption).foregroundStyle(theme.muted)
            }
            Button("Remove from frame") { confirmsDelete = true }
                .buttonStyle(SecondaryButtonStyle(destructive: true))
                .confirmationDialog("Remove this photo from the frame? It stays in your phone's library.", isPresented: $confirmsDelete, titleVisibility: .visible) {
                    Button("Remove", role: .destructive) {
                        Task { await store.deletePhoto(id: photo.id) }
                        dismiss()
                    }
                }
        }
    }
}
