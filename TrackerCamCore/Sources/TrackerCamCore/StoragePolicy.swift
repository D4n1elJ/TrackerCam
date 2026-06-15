/// Estimates remaining recording time and decides the low-space critical state. Plan §14.
/// Pure; the app supplies free-space (bytes) and a measured/estimated bitrate.
public struct StoragePolicy: Sendable {
    public var criticalSeconds: Double  // remaining recordable time at/below which we must stop
    public var reserveBytes: Int64      // headroom never consumed by recording

    public init(criticalSeconds: Double = 30, reserveBytes: Int64 = 200_000_000) {
        self.criticalSeconds = criticalSeconds
        self.reserveBytes = reserveBytes
    }

    /// Seconds of recording the free space allows at the given bitrate (0 if at/below reserve).
    public func recordableSeconds(freeBytes: Int64, bitrateBytesPerSecond: Double) -> Double {
        guard bitrateBytesPerSecond > 0 else { return .infinity }
        let usable = Double(max(0, freeBytes - reserveBytes))
        return usable / bitrateBytesPerSecond
    }

    /// True when remaining recordable time has reached the critical threshold.
    public func isCritical(freeBytes: Int64, bitrateBytesPerSecond: Double) -> Bool {
        guard bitrateBytesPerSecond > 0 else { return false }
        return recordableSeconds(freeBytes: freeBytes, bitrateBytesPerSecond: bitrateBytesPerSecond) <= criticalSeconds
    }

    /// Rough HEVC bitrate estimate (bytes/s) — ~0.07 bits per pixel·frame, a typical HEVC SDR ratio.
    public static func estimatedBitrateBytesPerSecond(width: Int, height: Int, fps: Double) -> Double {
        let bitsPerPixelFrame = 0.07
        let bitsPerSecond = Double(width * height) * fps * bitsPerPixelFrame
        return bitsPerSecond / 8.0
    }
}
