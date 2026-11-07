import SwiftUI

/// Pick the slideshow album, preview it, start the slideshow.
struct PhotosScreen: View {
    @Environment(PhotoLibrary.self) private var photos
    @Environment(KioskController.self) private var kiosk
    @State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !photos.canRead {
                accessCard
            } else {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(photos.selectedAlbum?.title ?? "No album chosen")
                            .font(.title.weight(.bold))
                        if let a = photos.selectedAlbum {
                            Text("\(a.count) photos\(a.isShared ? " · Shared album" : "")")
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    Spacer()
                    Button("Choose album", systemImage: "rectangle.stack") { choosing = true }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    Button("Start slideshow", systemImage: "play.fill") { kiosk.startSlideshowNow() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(photos.assetIDs.isEmpty)
                }
                if photos.assetIDs.isEmpty {
                    ContentUnavailableView {
                        Label("Pick an album", systemImage: "photo.on.rectangle.angled")
                    } description: {
                        Text("Tip: make an iCloud Shared Album (e.g. “Kitchen Frame”) and invite the family. Anything anyone adds from their iPhone shows up here.")
                    } actions: {
                        Button("Choose album") { choosing = true }.buttonStyle(.borderedProminent)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) {
                            ForEach(photos.assetIDs, id: \.self) { id in
                                Thumbnail(assetId: id)
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.canvas)
        .sheet(isPresented: $choosing) { AlbumPicker() }
        .onAppear { if photos.canRead { photos.reload() } }
        // Pick up changes made in the Settings app (e.g. switching to Full Access).
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            photos.reload()
        }
    }

    private var accessCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "photo.stack").font(.system(size: 44)).foregroundStyle(Palette.accent)
                Text("Show family photos when idle").font(.title.weight(.bold))
                Text("When nobody's using the iPad, CasitaCal can show a slideshow from an album you choose — like a photo frame.")
                    .foregroundStyle(Palette.inkSecondary)
                if photos.authorization == .denied || photos.authorization == .restricted {
                    Text("Photo access is off. Turn it on in Settings → Privacy & Security → Photos → CasitaCal → Full Access.")
                        .foregroundStyle(.orange)
                } else {
                    Button("Allow photo access") { Task { await photos.requestAccess() } }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AlbumPicker: View {
    @Environment(PhotoLibrary.self) private var photos
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                if photos.isLimited {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("CasitaCal only has Limited photo access", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.headline)
                            Text("It can only see the few photos you picked, so albums look empty. Choose Photos → Full Access in Settings.")
                                .foregroundStyle(.secondary)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 4)
                    }
                }
                let favorites = photos.albums.filter(\.isFavorites)
                let shared = photos.albums.filter(\.isShared)
                let mine = photos.albums.filter { !$0.isShared && !$0.isFavorites }
                if !favorites.isEmpty {
                    Section {
                        rows(favorites)
                    } footer: {
                        if favorites.first?.count == 0 {
                            Text("Empty on this iPad. Heart (♥) photos in the Photos app — or turn on iCloud Photos on the iPad (Settings → your name → iCloud → Photos) so your iPhone's favorites sync here.")
                        } else {
                            Text("Photos hearted (♥) in the Photos app on this iPad's Apple ID. With iCloud Photos on, hearts from that account's iPhone count too.")
                        }
                    }
                }
                if !shared.isEmpty {
                    Section {
                        rows(shared)
                    } header: {
                        Text("Shared albums")
                    } footer: {
                        Text("Best for the whole family: anyone invited can add photos from their own iPhone.")
                    }
                }
                if !mine.isEmpty { Section("My albums") { rows(mine) } }
                if photos.albums.isEmpty {
                    Text("No albums with photos found. On the iPad, open Photos and make sure iCloud Photos / Shared Albums are on.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Slideshow album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func rows(_ albums: [PhotoLibrary.Album]) -> some View {
        ForEach(albums) { a in
            Button {
                photos.selectedAlbumId = a.id
                dismiss()
            } label: {
                HStack {
                    Image(systemName: a.isFavorites ? "heart.fill" : (a.isShared ? "person.2.crop.square.stack" : "rectangle.stack"))
                        .foregroundStyle(a.isFavorites ? .pink : .primary)
                    Text(a.title)
                    Spacer()
                    Text("\(a.count)").foregroundStyle(.secondary)
                    if photos.selectedAlbumId == a.id {
                        Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                    }
                }
            }
            .foregroundStyle(.primary)
        }
    }
}

private struct Thumbnail: View {
    let assetId: String
    @Environment(PhotoLibrary.self) private var photos
    @State private var image: UIImage?

    var body: some View {
        Color(Palette.sidebar)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .task(id: assetId) { image = await photos.image(for: assetId, size: CGSize(width: 360, height: 360)) }
    }
}
