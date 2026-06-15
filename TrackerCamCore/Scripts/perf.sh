#!/usr/bin/env bash
# Per-frame core-math micro-benchmark (stdlib only; see LocalPerf/main.swift).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)/perf"
swiftc -O Sources/TrackerCamCore/*.swift LocalPerf/*.swift -o "$OUT"
"$OUT"
