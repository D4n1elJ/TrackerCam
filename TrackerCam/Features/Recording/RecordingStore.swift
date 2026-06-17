import Foundation
import Photos
import TrackerCamCore

/// Finalizes recordings: moves the writer's temp file into the app library and/or saves to Photos
/// per `SaveDestination` (plan §14). The writer always produces one temp file; copies happen here.
@MainActor
final class RecordingStore {
    let directory: URL

    init() {
        directory = URL.documentsDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    struct Result { var appURL: URL?; var savedToPhotos: Bool }

    /// Saved recordings in the app library, newest first.
    func recordings() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        return urls.filter { $0.pathExtension == "mov" }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
    }

    func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("ndjson"))
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
