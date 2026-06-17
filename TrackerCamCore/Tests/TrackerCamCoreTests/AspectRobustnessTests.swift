@testable import TrackerCamCore

// Aspect-ratio robustness across landscape/portrait/square. Plan §10 Aspect Ratio Modes.
func runAspectRobustnessTests() {
    let source = TCRect(x: 0, y: 0, width: 3840, height: 2160)

    // Portrait 9:16 max-zoom-out fits the source height, never exceeds source width.
    let port = CropPlanner.maxAspectCrop(aspect: 9.0 / 16.0, in: source)
    expectClose(port.height, 2160, tol: 1e-6, "portrait max height")
    expectClose(port.width, 2160 * 9.0 / 16.0, tol: 1e-6, "portrait max width")
    expect(port.width <= source.width + 1e-6, "portrait fits within source width")

    // Square 1:1 max-zoom-out is height-bound on a landscape source.
    let sq = CropPlanner.maxAspectCrop(aspect: 1.0, in: source)
    expectClose(sq.width, 2160, tol: 1e-6, "square max width")
    expectClose(sq.height, 2160, tol: 1e-6, "square max height")

    // requiredCropSize preserves the requested aspect and contains the subject (portrait case).
    let subj = TCRect(x: 0, y: 0, width: 400, height: 900)
    let cs = CropMath.requiredCropSize(forPaddedSubject: subj,
                                       targetSubjectHeightFraction: 0.5, outputAspect: 9.0 / 16.0)
    expectClose(cs.width / cs.height, 9.0 / 16.0, tol: 1e-9, "portrait crop keeps aspect")
    expect(cs.height >= subj.height - 1e-6, "crop contains subject height")
    expect(cs.width >= subj.width - 1e-6, "crop contains subject width")

    // fullFrame (aspect 0) → max crop is the whole source.
    let full = CropPlanner.maxAspectCrop(aspect: 0, in: source)
    expectClose(full.width, 3840, tol: 1e-6, "fullframe width")
    expectClose(full.height, 2160, tol: 1e-6, "fullframe height")
}
