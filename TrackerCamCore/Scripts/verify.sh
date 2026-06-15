#!/usr/bin/env bash
# Local verification harness for TrackerCamCore.
#
# SwiftPM and XCTest are unavailable under the Command Line Tools used in this dev sandbox,
# so we compile the library sources + LocalTests into one executable with swiftc and run it.
# In a full Xcode/CI environment, prefer `swift test` against the native XCTest target.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$(mktemp -d)/tcc-tests"
swiftc \
  Sources/TrackerCamCore/*.swift \
  LocalTests/*.swift \
  -o "$OUT"

RESULT="$("$OUT")"
echo "$RESULT"
echo "$RESULT" | grep -q "^RESULT: PASS" || { echo "verify.sh: tests failed"; exit 1; }
