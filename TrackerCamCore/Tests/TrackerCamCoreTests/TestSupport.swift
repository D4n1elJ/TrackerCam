@testable import TrackerCamCore

// Minimal assertion harness for the core-logic suites. The suites are plain functions that call
// `expect(...)` and accumulate into the shared counters below; the `coreLogic` @Test drives them
// all and asserts no failures. TrackerCamCore is framework-free (pure Swift) by design.
//
// Single-threaded use: the suites run sequentially inside one @Test, so the shared accumulator is
// never touched concurrently — nonisolated(unsafe) states that to the Swift 6 compiler.
nonisolated(unsafe) private(set) var checksRun = 0
nonisolated(unsafe) private(set) var failures: [String] = []

func expect(_ condition: Bool, _ message: @autoclosure () -> String,
            file: StaticString = #file, line: UInt = #line) {
    checksRun += 1
    if !condition {
        failures.append("\(file):\(line): \(message())")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String = "",
                               file: StaticString = #file, line: UInt = #line) {
    expect(actual == expected, "\(label) expected \(expected), got \(actual)", file: file, line: line)
}

func expectClose(_ actual: Double, _ expected: Double, tol: Double = 1e-6, _ label: String = "",
                 file: StaticString = #file, line: UInt = #line) {
    expect(abs(actual - expected) <= tol,
           "\(label) expected \(expected) ± \(tol), got \(actual)", file: file, line: line)
}

func expectRect(_ actual: TCRect, _ expected: TCRect, tol: Double = 1e-6, _ label: String = "",
                file: StaticString = #file, line: UInt = #line) {
    expectClose(actual.minX, expected.minX, tol: tol, "\(label).x", file: file, line: line)
    expectClose(actual.minY, expected.minY, tol: tol, "\(label).y", file: file, line: line)
    expectClose(actual.width, expected.width, tol: tol, "\(label).w", file: file, line: line)
    expectClose(actual.height, expected.height, tol: tol, "\(label).h", file: file, line: line)
}

// Returns normally (so buffered stdout flushes); the verify.sh script greps RESULT to set exit code.
func finish() {
    if failures.isEmpty {
        print("RESULT: PASS — \(checksRun) checks")
    } else {
        for f in failures { print("FAIL \(f)") }
        print("RESULT: FAIL — \(failures.count) failure(s) of \(checksRun) checks")
    }
}
