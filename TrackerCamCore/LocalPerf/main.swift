// Per-frame core-math micro-benchmark (stdlib only; no Foundation). Run via Scripts/perf.sh.
// Simulates the work TrackingEngine/CropController/CropPlanner/GuidanceEngine do every frame and
// reports per-frame cost vs the 16.67 ms (60 fps) budget.

let N = 120_000
let dt = 1.0 / 60.0
let source = TCRect(x: 0, y: 0, width: 3840, height: 2160)
let aspect = 16.0 / 9.0
let defaultSize = TCSize(width: 1920, height: 1080)

var kf = KalmanFilter2D(processNoise: 10, measurementNoise: 1)
var cc = CropController()
let planner = CropPlanner()
let guide = GuidanceEngine(deadZoneFraction: 0.08, lookaheadSeconds: 0.3)

var sink = 0.0
let clock = ContinuousClock()
let elapsed = clock.measure {
    for i in 0..<N {
        // A subject bouncing across the frame (no trig — keep it Foundation-free).
        let x = 300.0 + Double(i % 3200)
        let subject = TCPoint(x: x, y: 1000 + Double(i % 400))

        kf.predict(dt: dt)
        kf.update(measurement: subject)

        let padded = TCRect(center: kf.position, size: TCSize(width: 600, height: 400)).expanded(byFraction: 0.2)
        let size = CropMath.requiredCropSize(forPaddedSubject: padded,
                                             targetSubjectHeightFraction: 0.35, outputAspect: aspect)
        let composed = CropMath.compositionCenter(subjectCenter: kf.position, velocity: kf.velocity,
                                                  cropSize: size, leadFraction: 0.08, verticalOffsetFraction: -0.05)
        let planned = planner.plan(state: .tracking, secondsSinceLost: 0,
                                   lastCenter: kf.position, velocity: kf.velocity,
                                   trackingDesiredCenter: composed, trackingDesiredSize: size,
                                   defaultSize: defaultSize, source: source)
        let crop = cc.update(dt: dt, desiredCenter: planned.center, desiredSize: planned.size, source: source)
        let hint = guide.hint(subjectCenter: kf.position, predictedVelocity: kf.velocity, source: source, crop: crop)
        sink += crop.midX + hint.magnitude
    }
}

let c = elapsed.components
let totalNs = Double(c.seconds) * 1e9 + Double(c.attoseconds) / 1e9
let perFrameUs = totalNs / Double(N) / 1000.0
let budgetUs = 16_666.0
// round to 3 decimals without Foundation
func r(_ v: Double, _ places: Double = 1000) -> Double { (v * places).rounded() / places }
print("per-frame core math: \(r(perFrameUs)) us  (over \(N) frames)")
print("60 fps budget 16666 us -> core uses \(r(perFrameUs / budgetUs * 100, 10000))%")
print("(sink \(sink == 0 ? 0 : 1))")  // prevent dead-code elimination
