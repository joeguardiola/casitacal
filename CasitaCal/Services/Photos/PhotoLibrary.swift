import Observation
import Photos
import UIKit

/// Reads photos from one album the family chooses (ideally an iCloud Shared Album
/// that everyone can add to from their phones).
@MainActor
@Observable
final class PhotoLibrary {
    struct Album: Identifiable, Hashable {
        var id: String
        var title: String
        var count: Int
        var isShared: Bool
        var isFavorites = false
    }

    private(set) var authorization: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var albums: [Album] = []
    private(set) var assetIDs: [String] = []

    var selectedAlbumId: String? {
        didSet {
            UserDefaults.standard.set(selectedAlbumId, forKey: Self.albumKey)
            loadAssets()
        }
    }

    var selectedAlbum: Album? { albums.first { $0.id == selectedAlbumId } }
    var canRead: Bool { authorization == .authorized || authorization == .limited }
    var isLimited: Bool { authorization == .limited }

    private static let albumKey = "photos.albumId"
    private let imageManager = PHCachingImageManager()

    init() {
        selectedAlbumId = UserDefaults.standard.string(forKey: Self.albumKey)
        if canRead { reload() }
    }

    func requestAccess() async {
        authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if canRead { reload() }
    }

    func reload() {
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard canRead else { return }
        var found: [Album] = []
        let imagesOnly = PHFetchOptions()
        imagesOnly.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        func collect(_ type: PHAssetCollectionType, _ subtype: PHAssetCollectionSubtype, shared: Bool, favorites: Bool = false) {
            PHAssetCollection.fetchAssetCollections(with: type, subtype: subtype, options: nil)
                .enumerateObjects { collection, _, _ in
                    let count = PHAsset.fetchAssets(in: collection, options: imagesOnly).count
                    guard count > 0 || favorites else { return } // always offer Favorites, even if empty
                    found.append(Album(id: collection.localIdentifier,
                                       title: collection.localizedTitle ?? "Untitled",
                                       count: count, isShared: shared, isFavorites: favorites))
                }
        }
        collect(.smartAlbum, .smartAlbumFavorites, shared: false, favorites: true)
        collect(.album, .albumCloudShared, shared: true)
        collect(.album, .albumRegular, shared: false)
        func rank(_ a: Album) -> Int { a.isFavorites ? 0 : (a.isShared ? 1 : 2) }
        albums = found.sorted { (rank($0), $0.title) < (rank($1), $1.title) }
        loadAssets()
    }

    private func loadAssets() {
        guard canRead, let id = selectedAlbumId,
              let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
        else { assetIDs = []; return }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var ids: [String] = []
        PHAsset.fetchAssets(in: collection, options: options).enumerateObjects { a, _, _ in ids.append(a.localIdentifier) }
        assetIDs = ids
    }

    /// Loads one image, downloading from iCloud if needed (shared albums live in the cloud).
    func image(for assetId: String, size: CGSize, contentMode: PHImageContentMode = .aspectFill) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        let manager = imageManager
        return await withCheckedContinuation { continuation in
            manager.requestImage(for: asset, targetSize: size, contentMode: contentMode, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
