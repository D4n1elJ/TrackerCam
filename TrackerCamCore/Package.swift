// swift-tools-version: 6.2
import PackageDescription

// TrackerCamCore — platform-agnostic logic for TrackerCam (see ../PLAN.md).
//
// This package deliberately contains NO AVFoundation / Vision / Metal / UIKit code so it
// compiles and unit-tests on macOS with `swift test` (no iOS device or full Xcode required).
// The iOS app target links this package and provides the hardware/UI layers.
// swift-tools-version 6.0 defaults to the Swift 6 language mode (strict concurrency).
let package = Package(
    name: "TrackerCamCore",
    // No `platforms:` line: keeps the manifest compatible with the Command Line Tools
    // PackageDescription ABI for `swift test`. The iOS app target (XcodeGen, full Xcode)
    // sets the real iOS 26 deployment target; the package adopts the consumer's target on iOS.
    products: [
        .library(name: "TrackerCamCore", targets: ["TrackerCamCore"]),
    ],
    // No SwiftPM test target: the core is verified via Scripts/verify.sh (swiftc harness in
    // LocalTests/), which avoids the broken SwiftPM/XCTest in this environment. LocalTests/ lives
    // outside Sources/ so it is not compiled into the library.
    targets: [
        .target(name: "TrackerCamCore"),
    ]
)
