@testable import TrackerCamCore

// Crop geometry math. Plan §10 Reframe, Crop & Stabilization.
func runCropMathTests() {
    // --- expanded(byFraction:) keeps center, grows each dimension by the fraction (total) ---
    let box = TCRect(x: 100, y: 100, width: 200, height: 100)
    let padded = box.expanded(byFraction: 0.2) // +20% total → 240×120, centered
    expectRect(padded, TCRect(x: 80, y: 90, width: 240, height: 120), "expanded")

    // --- compound subject = union of horse + rider, then padded ---
    let horse = TCRect(x: 1000, y: 800, width: 600, height: 400)
    let rider = TCRect(x: 1100, y: 600, width: 200, height: 300) // overlaps top of horse
    let compound = CropMath.compoundSubject(horse: horse, rider: rider, padding: 0.0)
    expectRect(compound, TCRect(x: 1000, y: 600, width: 600, height: 600), "compound union")

    // --- requiredCropSize: height = paddedHeight / targetFraction, width = height * aspect ---
    let aspect = 16.0 / 9.0
    let subj = TCRect(x: 0, y: 0, width: 628, height: 540)
    let size = CropMath.requiredCropSize(forPaddedSubject: subj,
                                         targetSubjectHeightFraction: 0.35,
                                         outputAspect: aspect)
    expectClose(size.height, 540 / 0.35, tol: 1e-6, "crop height")
    expectClose(size.width, (540 / 0.35) * aspect, tol: 1e-6, "crop width")
    expect(size.width >= subj.width, "crop width contains subject")

    // --- requiredCropSize derives from width when the subject is very wide ---
    let wide = TCRect(x: 0, y: 0, width: 3000, height: 200)
    let wideSize = CropMath.requiredCropSize(forPaddedSubject: wide,
                                             targetSubjectHeightFraction: 0.35,
                                             outputAspect: aspect)
    expect(wideSize.width >= wide.width, "wide crop contains subject width")
    expectClose(wideSize.width / wideSize.height, aspect, tol: 1e-9, "wide keeps aspect")

    // --- clampedCrop: oversized crop scales to fit source, preserving aspect ---
    let source = TCRect(x: 0, y: 0, width: 3840, height: 2160)
    let huge = CropMath.clampedCrop(center: TCPoint(x: 1920, y: 1080),
                                    size: TCSize(width: 4000, height: 2250),
                                    source: source)
    expectRect(huge, TCRect(x: 0, y: 0, width: 3840, height: 2160), tol: 1e-6, "oversized → source")

    // --- clampedCrop: pushes a near-edge crop fully inside the source ---
    let edge = CropMath.clampedCrop(center: TCPoint(x: 100, y: 100),
                                    size: TCSize(width: 1920, height: 1080),
                                    source: source)
    expectRect(edge, TCRect(x: 0, y: 0, width: 1920, height: 1080), tol: 1e-6, "edge clamp")

    // --- composition center: motion lead (forward) + vertical offset (subject lower → center up) ---
    let center = CropMath.compositionCenter(subjectCenter: TCPoint(x: 1000, y: 500),
                                            velocity: TCPoint(x: 10, y: 0),
                                            cropSize: TCSize(width: 2000, height: 1125),
                                            leadFraction: 0.08,
                                            verticalOffsetFraction: -0.05)
    expectClose(center.x, 1000 + 2000 * 0.08, tol: 1e-6, "lead x") // 1160
    expectClose(center.y, 500 + 1125 * -0.05, tol: 1e-6, "vertical offset")  // 443.75

    // zero velocity → no lead.
    let still = CropMath.compositionCenter(subjectCenter: TCPoint(x: 1000, y: 500),
                                           velocity: .zero,
                                           cropSize: TCSize(width: 2000, height: 1125),
                                           leadFraction: 0.08,
                                           verticalOffsetFraction: 0.0)
    expectClose(still.x, 1000, tol: 1e-9, "no lead when still")

    // --- headroom per edge (0 at the wall, 1 at the far side) ---
    let hrCornered = CropMath.headroom(crop: TCRect(x: 0, y: 0, width: 1920, height: 1080), source: source)
    expectClose(hrCornered.left, 0, tol: 1e-9, "left headroom at wall")
    expectClose(hrCornered.right, 1, tol: 1e-9, "right headroom far")
    expectClose(hrCornered.top, 0, tol: 1e-9, "top headroom at wall")
    expectClose(hrCornered.bottom, 1, tol: 1e-9, "bottom headroom far")

    let hrCentered = CropMath.headroom(crop: TCRect(x: 960, y: 540, width: 1920, height: 1080), source: source)
    expectClose(hrCentered.left, 0.5, tol: 1e-9, "centered left")
    expectClose(hrCentered.right, 0.5, tol: 1e-9, "centered right")

    // zero pan room → zero headroom, no divide-by-zero.
    let hrFull = CropMath.headroom(crop: source, source: source)
    expectClose(hrFull.left, 0, tol: 1e-9, "no pan room left")
    expectClose(hrFull.right, 0, tol: 1e-9, "no pan room right")
}
