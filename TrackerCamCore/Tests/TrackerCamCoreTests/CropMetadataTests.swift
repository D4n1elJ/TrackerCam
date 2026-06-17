@testable import TrackerCamCore

// Sidecar crop metadata (NDJSON) for post-recrop / replay overlay. Plan §14 Sidecar Format.
func runCropMetadataTests() {
    let r = CropFrameRecord(
        sequence: 42, ptsValue: 1260, ptsTimescale: 600,
        crop: TCRect(x: 812.5, y: 456.8, width: 2133.3, height: 1200.0),
        subject: TCRect(x: 1402, y: 721, width: 628, height: 540),
        confidence: 0.87, state: "tracking", predicted: true)
    let line = r.jsonLine

    expect(line.contains("\"seq\":42"), "seq present")
    expect(line.contains("\"pts\":{\"v\":1260,\"ts\":600}"), "pts present")
    expect(line.contains("\"state\":\"tracking\""), "state present")
    expect(line.contains("\"predicted\":true"), "predicted present")
    expect(line.contains("\"confidence\":0.87"), "confidence present")
    expect(line.contains("\"crop\":{"), "crop object present")
    expect(line.contains("\"subject\":{"), "subject object present")
    expect(!line.contains("\n"), "single line")

    // nil subject serializes as null.
    let r2 = CropFrameRecord(sequence: 1, ptsValue: 0, ptsTimescale: 600,
                             crop: TCRect(x: 0, y: 0, width: 100, height: 100),
                             subject: nil, confidence: 0, state: "idle", predicted: false)
    expect(r2.jsonLine.contains("\"subject\":null"), "nil subject → null")
    expect(r2.jsonLine.contains("\"predicted\":false"), "predicted false")

    // Log accumulates NDJSON (one record per line).
    var log = CropMetadataLog()
    log.append(r)
    log.append(r2)
    expectEqual(log.count, 2, "log count")
    let nd = log.ndjson()
    expectEqual(nd.split(separator: "\n").count, 2, "two ndjson lines")
}
