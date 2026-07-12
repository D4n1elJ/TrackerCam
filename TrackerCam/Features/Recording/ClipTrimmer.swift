import AVFoundation
import Foundation

/// Exports a time-range subclip of a library recording into a new `.mov` next to the source.
enum ClipTrimmer {
    enum TrimError: Error, LocalizedError {
        case invalidRange
        case noVideoTrack
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidRange: return "Trim range is empty or outside the clip."
            case .noVideoTrack: return "Clip has no video track."
            case .exportFailed(let msg): return msg
            }
        }
    }

    /// Trim `source` to `[start, end]` seconds and write a new file in the same directory.
    /// - Returns: URL of the new clip.
    static func trim(source: URL, start: Double, end: Double) async throws -> URL {
        guard end > start, start >= 0 else { throw TrimError.invalidRange }

        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let durationSec = duration.seconds
        guard durationSec.isFinite, durationSec > 0 else { throw TrimError.invalidRange }
        let clampedStart = min(max(0, start), durationSec)
        let clampedEnd = min(max(clampedStart + 0.1, end), durationSec)
        guard clampedEnd > clampedStart else { throw TrimError.invalidRange }

        let startTime = CMTime(seconds: clampedStart, preferredTimescale: 600)
        let endTime = CMTime(seconds: clampedEnd, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startTime, end: endTime)

        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetHighestQuality) else {
            throw TrimError.exportFailed("Could not create export session.")
        }

        let base = source.deletingPathExtension().lastPathComponent
        let stamp = Int(Date().timeIntervalSince1970)
        let dest = source.deletingLastPathComponent()
            .appending(path: "\(base)_trim_\(stamp)")
            .appendingPathExtension("mov")
        try? FileManager.default.removeItem(at: dest)

        session.outputURL = dest
        session.outputFileType = .mov
        session.timeRange = timeRange

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { cont.resume() }
        }
        if session.status == .completed {
            return dest
        }
        let msg = session.error?.localizedDescription ?? "Export status \(session.status.rawValue)"
        throw TrimError.exportFailed(msg)
    }
}
