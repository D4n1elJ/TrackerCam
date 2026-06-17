#!/usr/bin/env bash
# Local verification harness for TrackerCamCore.
#
# Runs the framework-free core-logic suites through Swift Testing (`swift test`). The suites live in
# Tests/TrackerCamCoreTests and are driven sequentially by the `coreLogic` @Test (see TestSupport.swift).
# Uses the full Xcode toolchain when available (Command Line Tools alone lacks a usable test runner).
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -d /Applications/Xcode.app ]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

swift test
