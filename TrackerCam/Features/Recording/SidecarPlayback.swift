import Foundation
import CoreGraphics

/// One parsed sidecar frame: the subject box in the recorded (cropped) frame's normalized [0,1]
/// space, at a playback time. Built from the `.ndjson` written during recording (plan §14).
struct SidecarFrame {
    let seconds: Double
    let subject: CGRect?   // normalized within the output frame, nil if none
}

enum Sidecar {
    /// Load + parse the `.ndjson` sitting next to a recording. Empty if absent/unreadable.
    static func load(videoURL: URL) -> [SidecarFrame] {
        let url = videoURL.deletingPathExtension().appendingPathExtension("ndjson")
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }

        var frames: [SidecarFrame] = []
        for line in text.split(separator: "\n") {
            guard let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let pts = obj["pts"] as? [String: Any],
                  let v = num(pts["v"]), let ts = num(pts["ts"]), ts > 0,
                  let crop = obj["crop"] as? [String: Any] else { continue }

            let cx = num(crop["x"]) ?? 0, cy = num(crop["y"]) ?? 0
            let cw = num(crop["w"]) ?? 0, ch = num(crop["h"]) ?? 0
            var subject: CGRect?
            if let s = obj["subject"] as? [String: Any], cw > 0, ch > 0,
               let sx = num(s["x"]), let sy = num(s["y"]), let sw = num(s["w"]), let sh = num(s["h"]) {
                subject = CGRect(x: (sx - cx) / cw, y: (sy - cy) / ch, width: sw / cw, height: sh / ch)
            }
            frames.append(SidecarFrame(seconds: v / ts, subject: subject))
        }
        return frames
    }

    /// Subject box (normalized) at or just before `time`. Frames are in ascending time order.
    static func subject(at time: Double, in frames: [SidecarFrame]) -> CGRect? {
        guard !frames.isEmpty else { return nil }
        var lo = 0, hi = frames.count - 1, best = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if frames[mid].seconds <= time { best = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return frames[best].subject
    }

    private static func num(_ a: Any?) -> Double? { (a as? NSNumber)?.doubleValue }
}
