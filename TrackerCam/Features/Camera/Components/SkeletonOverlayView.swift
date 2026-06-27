import SwiftUI
import TrackerCamCore

/// Draws live skeletons (bones + joints) over the full-frame preview. Skeleton joint points are
/// normalized [0,1] top-left in the displayed image, so we map them through the same
/// `PreviewGeometry.textureDrawRect` the bounding-box overlay uses, keeping them registered to the
/// preview regardless of aspect-fit/fill letterboxing.
struct SkeletonOverlayView: View {
    let skeletons: [SkeletonOverlay]
    let outputSize: CGSize
    let aspectFill: Bool
    let viewSize: CGSize

    var body: some View {
        Canvas { context, _ in
            let draw = PreviewGeometry.textureDrawRect(viewSize: viewSize,
                                                       outputSize: outputSize,
                                                       aspectFill: aspectFill)
            for skeleton in skeletons {
                let joints = skeleton.joints
                let pts = joints.map { joint in
                    CGPoint(x: draw.minX + joint.x * draw.width,
                            y: draw.minY + joint.y * draw.height)
                }

                // Bones — only between joints that are BOTH present this frame (skip absent joints,
                // which otherwise anchor to the top-left corner and draw stray lines).
                var bonePath = Path()
                for bone in skeleton.bones
                where bone.a < joints.count && bone.b < joints.count
                    && joints[bone.a].isPresent && joints[bone.b].isPresent {
                    bonePath.move(to: pts[bone.a])
                    bonePath.addLine(to: pts[bone.b])
                }
                context.stroke(bonePath,
                               with: .color(color(for: skeleton.kind).opacity(0.9)),
                               style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                // Joints — present ones only.
                for (i, p) in pts.enumerated() where joints[i].isPresent {
                    let r: CGFloat = 4 + 3 * joints[i].confidence
                    let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
                    context.fill(Path(ellipseIn: rect), with: .color(.white))
                    context.stroke(Path(ellipseIn: rect),
                                   with: .color(color(for: skeleton.kind)),
                                   lineWidth: 2)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeOut(duration: 0.08), value: skeletons)
    }

    private func color(for kind: SkeletonOverlay.Kind) -> Color {
        switch kind {
        case .human: return .green
        case .animal: return .orange
        }
    }
}
