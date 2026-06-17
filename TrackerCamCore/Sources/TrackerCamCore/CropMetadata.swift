/// Per-frame crop/subject record for the optional sidecar (plan §14 Sidecar Format).
/// Framework-free manual NDJSON (the core avoids Foundation), so it's unit-testable here.
public struct CropFrameRecord: Equatable, Sendable {
    public var sequence: Int
    public var ptsValue: Int64
    public var ptsTimescale: Int32
    public var crop: TCRect
    public var subject: TCRect?
    public var confidence: Double
    public var state: String
    public var predicted: Bool

    public init(sequence: Int, ptsValue: Int64, ptsTimescale: Int32,
                crop: TCRect, subject: TCRect?, confidence: Double, state: String, predicted: Bool) {
        self.sequence = sequence
        self.ptsValue = ptsValue
        self.ptsTimescale = ptsTimescale
        self.crop = crop
        self.subject = subject
        self.confidence = confidence
        self.state = state
        self.predicted = predicted
    }

    public var jsonLine: String {
        func rect(_ r: TCRect) -> String {
            "{\"x\":\(r.x),\"y\":\(r.y),\"w\":\(r.width),\"h\":\(r.height)}"
        }
        let subjectJSON = subject.map(rect) ?? "null"
        return "{\"seq\":\(sequence),"
            + "\"pts\":{\"v\":\(ptsValue),\"ts\":\(ptsTimescale)},"
            + "\"crop\":\(rect(crop)),"
            + "\"subject\":\(subjectJSON),"
            + "\"confidence\":\(confidence),"
            + "\"state\":\"\(state)\","
            + "\"predicted\":\(predicted)}"
    }
}

/// Accumulates `CropFrameRecord`s and serializes newline-delimited JSON.
public struct CropMetadataLog: Sendable {
    public private(set) var lines: [String] = []
    public init() {}
    public var count: Int { lines.count }
    public mutating func append(_ record: CropFrameRecord) { lines.append(record.jsonLine) }
    public func ndjson() -> String { lines.joined(separator: "\n") }
}
