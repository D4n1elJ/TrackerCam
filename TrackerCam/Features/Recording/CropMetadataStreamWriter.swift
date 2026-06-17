import Foundation
import TrackerCamCore

/// Incremental NDJSON writer for crop metadata sidecars. Keeps long recordings from accumulating
/// per-frame metadata in memory before finalization. Main-actor owned by `CameraViewModel`.
@MainActor
final class CropMetadataStreamWriter {
    private let handle: FileHandle
    private var isClosed = false

    init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    func append(_ record: CropFrameRecord) {
        guard !isClosed else { return }
        guard let data = (record.jsonLine + "\n").data(using: .utf8) else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            close()
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        try? handle.synchronize()
        try? handle.close()
    }

    deinit {
        try? handle.close()
    }
}
