import Vision
import CoreVideo
import TrackerCamCore

/// Rider body-pose estimation — the iOS-native stand-in for MediaPipe Pose.
///
/// Uses Vision's `VNDetectHumanBodyPoseRequest`, which runs ON-DEVICE on the Neural Engine and needs
/// NO third-party dependency (unlike MediaPipe, which ships as a CocoaPod). It returns up to 19 body
/// landmarks in normalized, bottom-left-origin coordinates; we convert to top-left pixel space so the
/// pure `PoseGeometry` math and the annotator share one coordinate convention.
///
/// SIMULATOR NOTE: like the Core ML detectors, body-pose leans on ANE/espresso and may fail in the
/// simulator ("Failed to create espresso context"). It is reliable on device. The analyzer treats a
/// nil result as "no rider this frame" and continues.
///
/// SWAP-IN: to use MediaPipe instead (e.g. for parity with a desktop pipeline), implement
/// `RiderPosing` with the MediaPipe Tasks `PoseLandmarker` and map its 33 landmarks to `TCRiderJoint`.
protocol RiderPosing: Sendable {
    /// Estimate the rider skeleton for one frame. `imageSize` is the pixel size of `pixelBuffer`.
    /// `regionOfInterest` (optional, normalized bottom-left like Vision) restricts the search to the
    /// rider box from detection for speed/accuracy.
    func skeleton(in pixelBuffer: CVPixelBuffer,
                  imageSize: TCSize,
                  regionOfInterest: CGRect?) -> TCSkeleton?
}

final class VisionRiderPoseEstimator: RiderPosing {
    private let minJointConfidence: Float

    /// Vision joint → our portable enum. Only the joints we measure are mapped.
    private static let mapping: [VNHumanBodyPoseObservation.JointName: TCRiderJoint] = [
        .nose: .nose, .neck: .neck,
        .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder,
        .leftElbow: .leftElbow, .rightElbow: .rightElbow,
        .leftWrist: .leftWrist, .rightWrist: .rightWrist,
        .leftHip: .leftHip, .rightHip: .rightHip,
        .leftKnee: .leftKnee, .rightKnee: .rightKnee,
        .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle,
        .root: .root,
    ]

    init(minJointConfidence: Float = 0.2) {
        self.minJointConfidence = minJointConfidence
    }

    func skeleton(in pixelBuffer: CVPixelBuffer,
                  imageSize: TCSize,
                  regionOfInterest: CGRect?) -> TCSkeleton? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        if let roi = regionOfInterest { request.regionOfInterest = roi }
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let candidates = request.results?.compactMap {
            Self.skeleton(from: $0, imageSize: imageSize, minJointConfidence: minJointConfidence)
        } ?? []
        guard !candidates.isEmpty else { return nil }

        return candidates.max {
            Self.score($0, imageSize: imageSize, regionOfInterest: regionOfInterest) <
                Self.score($1, imageSize: imageSize, regionOfInterest: regionOfInterest)
        }
    }

    private static func skeleton(from observation: VNHumanBodyPoseObservation,
                                 imageSize: TCSize,
                                 minJointConfidence: Float) -> TCSkeleton? {
        guard let recognized = try? observation.recognizedPoints(.all) else { return nil }
        var skeleton = TCSkeleton()
        for (visionName, riderJoint) in Self.mapping {
            guard let pt = recognized[visionName], pt.confidence >= minJointConfidence else { continue }
            // Vision: normalized, origin bottom-left. Convert to top-left pixel space.
            let px = Double(pt.location.x) * imageSize.width
            let py = (1 - Double(pt.location.y)) * imageSize.height
            skeleton.set(riderJoint.rawValue,
                         TCJoint(point: TCPoint(x: px, y: py), confidence: Double(pt.confidence)))
        }
        return skeleton.joints.isEmpty ? nil : skeleton
    }

    private static func score(_ skeleton: TCSkeleton,
                              imageSize: TCSize,
                              regionOfInterest: CGRect?) -> Double {
        let completeness = Double(skeleton.joints.count) / Double(mapping.count)
        var score = skeleton.meanConfidence * 0.65 + completeness * 0.35

        if let regionOfInterest, let box = boundingBox(of: skeleton) {
            let roiCenter = TCPoint(
                x: Double(regionOfInterest.midX) * imageSize.width,
                y: (1 - Double(regionOfInterest.midY)) * imageSize.height)
            let dx = box.center.x - roiCenter.x
            let dy = box.center.y - roiCenter.y
            let diag = max(1, (imageSize.width * imageSize.width + imageSize.height * imageSize.height).squareRoot())
            let proximity = 1 - min(1, (dx * dx + dy * dy).squareRoot() / diag)
            score += proximity * 0.25
        }

        return score
    }

    private static func boundingBox(of skeleton: TCSkeleton) -> TCRect? {
        let pts = skeleton.joints.values.map(\.point)
        guard let first = pts.first else { return nil }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in pts {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return TCRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
