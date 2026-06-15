// Recording storage estimation. Plan §14 Save Destination / low-space handling.
func runStoragePolicyTests() {
    let p = StoragePolicy(criticalSeconds: 30, reserveBytes: 0)

    // recordableSeconds = (free - reserve) / bitrate.
    expectClose(p.recordableSeconds(freeBytes: 1_000_000_000, bitrateBytesPerSecond: 10_000_000),
                100, tol: 1e-6, "recordable seconds")

    // Critical when remaining time ≤ criticalSeconds.
    expect(p.isCritical(freeBytes: 200_000_000, bitrateBytesPerSecond: 10_000_000),
           "20s remaining → critical")
    expect(!p.isCritical(freeBytes: 1_000_000_000, bitrateBytesPerSecond: 10_000_000),
           "100s remaining → not critical")

    // Reserve is subtracted before estimating.
    let pr = StoragePolicy(criticalSeconds: 30, reserveBytes: 500_000_000)
    expectClose(pr.recordableSeconds(freeBytes: 1_000_000_000, bitrateBytesPerSecond: 10_000_000),
                50, tol: 1e-6, "reserve subtracted")

    // Never returns negative time when below the reserve.
    expectClose(pr.recordableSeconds(freeBytes: 100_000_000, bitrateBytesPerSecond: 10_000_000),
                0, tol: 1e-6, "clamped at zero")
    expect(pr.isCritical(freeBytes: 100_000_000, bitrateBytesPerSecond: 10_000_000),
           "below reserve → critical")

    // Zero/invalid bitrate is treated as "plenty" (avoids divide-by-zero false alarms).
    expect(!p.isCritical(freeBytes: 1_000, bitrateBytesPerSecond: 0), "zero bitrate → not critical")

    // A rough HEVC 1080p60 bitrate estimate is positive and sane (< 8 MB/s).
    let est = StoragePolicy.estimatedBitrateBytesPerSecond(width: 1920, height: 1080, fps: 60)
    expect(est > 0 && est < 8_000_000, "1080p60 estimate in range")
}
