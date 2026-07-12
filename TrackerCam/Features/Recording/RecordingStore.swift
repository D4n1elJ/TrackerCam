import Foundation
import Photos
import TrackerCamCore

/// Finalizes recordings: moves the writer's temp file into the app library and/or saves to Photos
/// per `SaveDestination` (plan §14). The writer always produces one temp file; copies happen here.
@MainActor
final class RecordingStore {
    let directory: URL
    private let favoritesURL: URL

    init() {
        directory = URL.documentsDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        favoritesURL = directory.appending(path: ".favorites.json")
    }

    struct Result { var appURL: URL?; var savedToPhotos: Bool }

    /// Library row model for UI (newest first; favorites pinned to the top).
    struct RecordingItem: Identifiable, Hashable {
        var id: String { url.absoluteString }
        var url: URL
        var displayName: String
        var modified: Date
        var byteCount: Int64
        var isFavorite: Bool
        var durationSeconds: Double?
    }

    /// Saved recordings in the app library, favorites first then newest.
    func recordings() -> [URL] {
        items().map(\.url)
    }

    func items() -> [RecordingItem] {
        let favorites = loadFavorites()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles])) ?? []
        let movs = urls.filter { $0.pathExtension.lowercased() == "mov" }
        let items: [RecordingItem] = movs.map { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let sidecar = url.deletingPathExtension().appendingPathExtension("ndjson")
            let sidecarBytes = Int64((try? sidecar.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            let videoBytes = Int64(values?.fileSize ?? 0)
            return RecordingItem(
                url: url,
                displayName: url.deletingPathExtension().lastPathComponent,
                modified: values?.contentModificationDate ?? .distantPast,
                byteCount: videoBytes + sidecarBytes,
                isFavorite: favorites.contains(url.lastPathComponent),
                durationSeconds: nil)
        }
        return items.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
            return $0.modified > $1.modified
        }
    }

    /// Total bytes used by app-library clips + sidecars.
    func libraryByteCount() -> Int64 {
        items().reduce(0) { $0 + $1.byteCount }
    }

    func delete(_ url: URL) {
        let name = url.lastPathComponent
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("ndjson"))
        var favorites = loadFavorites()
        if favorites.remove(name) != nil {
            saveFavorites(favorites)
        }
    }

    /// Rename a clip (and its `.ndjson` sidecar if present). Returns the new URL or nil on failure.
    @discardableResult
    func rename(_ url: URL, to newBaseName: String) -> URL? {
        let trimmed = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Keep filesystem-safe names.
        let safe = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let dest = directory.appending(path: safe).appendingPathExtension("mov")
        guard dest != url else { return url }
        guard !FileManager.default.fileExists(atPath: dest.path) else { return nil }
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            let oldSidecar = url.deletingPathExtension().appendingPathExtension("ndjson")
            let newSidecar = dest.deletingPathExtension().appendingPathExtension("ndjson")
            if FileManager.default.fileExists(atPath: oldSidecar.path) {
                try? FileManager.default.removeItem(at: newSidecar)
                try? FileManager.default.moveItem(at: oldSidecar, to: newSidecar)
            }
            var favorites = loadFavorites()
            if favorites.remove(url.lastPathComponent) != nil {
                favorites.insert(dest.lastPathComponent)
                saveFavorites(favorites)
            }
            return dest
        } catch {
            return nil
        }
    }

    func setFavorite(_ url: URL, isFavorite: Bool) {
        var favorites = loadFavorites()
        if isFavorite {
            favorites.insert(url.lastPathComponent)
        } else {
            favorites.remove(url.lastPathComponent)
        }
        saveFavorites(favorites)
    }

    func isFavorite(_ url: URL) -> Bool {
        loadFavorites().contains(url.lastPathComponent)
    }

    /// - Parameters:
    ///   - tempURL: the writer's finalized temp file.
    ///   - destination: where the user wants it.
    ///   - mode/resolution: for the filename (plan §14 naming).
    func finalize(tempURL: URL,
                  destination: SaveDestination,
                  mode: String,
                  resolution: String) async -> Result {
        let name = "TrackerCam_\(Self.timestamp())_\(mode)_\(resolution).mov"
        var appURL: URL?
        var savedToPhotos = false

        switch destination {
        case .app, .both:
            let dest = directory.appending(path: name)
            do {
                if destination == .both {
                    try FileManager.default.copyItem(at: tempURL, to: dest)
                } else {
                    try FileManager.default.moveItem(at: tempURL, to: dest)
                }
                appURL = dest
            } catch {
                appURL = nil
            }
        case .photos:
            break
        }

        if destination == .photos || destination == .both {
            savedToPhotos = await Self.saveToPhotos(url: tempURL)
        }

        // Clean up the temp file if it wasn't moved into the library.
        if destination != .app {
            try? FileManager.default.removeItem(at: tempURL)
        }
        return Result(appURL: appURL, savedToPhotos: savedToPhotos)
    }

    private func loadFavorites() -> Set<String> {
        guard let data = try? Data(contentsOf: favoritesURL),
              let names = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(names)
    }

    private func saveFavorites(_ favorites: Set<String>) {
        let names = Array(favorites).sorted()
        guard let data = try? JSONEncoder().encode(names) else { return }
        try? data.write(to: favoritesURL, options: .atomic)
    }

    private static func saveToPhotos(url: URL) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, _ in
                cont.resume(returning: success)
            }
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}
