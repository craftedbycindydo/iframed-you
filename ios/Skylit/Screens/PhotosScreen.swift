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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let store: FrameStore
    let id: String
    let maxEdge: Int
    var fills = true
    @State private var image: CGImage?
    @State private var failed = false

    private var key: String { "\(id)-\(maxEdge)" }

    var body: some View {
        ZStack {
            theme.fill
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: fills ? .fill : .fit)
                    .transition(.opacity)
            } else if failed {
                Image(systemName: "photo").foregroundStyle(Theme.secondaryLabel)
            } else {
                ProgressView()
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
            withAnimation(reduceMotion ? Motion.reduced : Motion.state) { image = decoded }
        }
    }
}

struct PhotosScreen: View {
    @Environment(\.theme) private var theme
    let store: FrameStore
    let openSetup: () -> Void
    @State private var picks: [PhotosPickerItem] = []
    @State private var viewing: PhotoRef?
    @State private var removing: PhotoRef?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 3)

    var body: some View {
        NavigationStack {
            ThemedList {
                if let upload = store.upload {
                    Section {
                        ProgressView(value: upload.overall) {
                            Text("Sending photo \(upload.index + 1) of \(upload.total)").font(.rowTitle)
                        } currentValueLabel: {
                            Text("Keep the app open until this finishes.").font(.rowSubtitle).foregroundStyle(Theme.secondaryLabel)
                        }
                        .tint(theme.tint)
                    }
                }
                if store.state?.settings.supportsICloudAlbum == true {
                    Section {
                        Button(action: openSetup) {
                            RowLabel(albumTitle, subtitle: albumDetail, symbol: "icloud", symbolTint: theme.tint) {
                                RowChevron()
                            }
                        }
                        .buttonStyle(RowButtonStyle())
                        .accessibilityHint("Opens the Frame tab")
                    }
                }
                if store.photos.isEmpty, store.upload == nil {
                    Section {
                        ContentUnavailableView {
                            Label("No photos from a phone yet", systemImage: "photo.on.rectangle.angled")
                        } description: {
                            Text("Photos you add join the frame's slideshow. They are resized, then sent encrypted between this phone and your frame.")
                        } actions: {
                            PhotosPicker(selection: $picks, maxSelectionCount: 30, matching: .images) {
                                Text("Add photos")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        LazyVGrid(columns: columns, spacing: Space.xs) {
                            ForEach(store.photos) { photo in
                                Button {
                                    viewing = photo
                                } label: {
                                    Color.clear
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay(FramePhoto(store: store, id: photo.id, maxEdge: 360))
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                                }
                                .buttonStyle(RowButtonStyle())
                                .contextMenu {
                                    Button("Remove from Frame", systemImage: "trash", role: .destructive) { removing = photo }
                                }
                                .accessibilityLabel("Photo added \(added(photo))")
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .listSectionSpacing(Space.l)
            .refreshable {
                await store.refresh()
                await store.loadPhotos()
            }
            .screenHeader("Photos", status: store.connectionStatus ?? countLine,
                          statusSymbol: store.connectionSymbol ?? "photo.on.rectangle.angled") {
                PhotosPicker(selection: $picks, maxSelectionCount: 30, matching: .images) {
                    Label("Add photos", systemImage: "plus")
                }
                .headerAction(prominent: true)
                .disabled(store.upload != nil)
            }
        }
        .stateAnimation(store.upload == nil)
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
        .confirmationDialog("Remove this photo from the frame? It stays in your phone's library.",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let id = removing?.id { Task { await store.deletePhoto(id: id) } }
            }
        }
    }

    private var albumTitle: String {
        guard let album = store.state?.settings.icloudAlbum else { return "Mirror an iCloud shared album" }
        return album.name.isEmpty ? "iCloud shared album" : album.name
    }

    private var albumDetail: String {
        guard let album = store.state?.settings.icloudAlbum else { return "Set it up once in Frame." }
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
        NavigationStack {
            FramePhoto(store: store, id: photo.id, maxEdge: 1600, fills: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.background.ignoresSafeArea())
                .navigationTitle(added.isEmpty ? "Photo" : "Added \(added)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Remove from frame", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                    }
                }
                .confirmationDialog("Remove this photo from the frame? It stays in your phone's library.", isPresented: $confirmsDelete, titleVisibility: .visible) {
                    Button("Remove", role: .destructive) {
                        Task { await store.deletePhoto(id: photo.id) }
                        dismiss()
                    }
                }
        }
    }
}
