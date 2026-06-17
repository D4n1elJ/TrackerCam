#!/usr/bin/env bash
# Rebuild TrackerCam and (re)install it to the connected/networked iPhone.
# Retries through device sleep/disconnect; only fails on real signing/compile errors.
# Requires the phone unlocked, Developer Mode on, same LAN or cable.
#
#   ./deploy.sh
#   DEVICE="Daniels Phone" ./deploy.sh
set -uo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$(dirname "$0")"
DEV="${DEVICE:-Daniels Phone}"

# Always clean: incremental builds in this env unreliably re-copy resources (Info.plist, shaders,
# assets), which has caused stale bundles. A full rebuild is slower but never stale.
rm -rf .build-xcode

ok=0
for i in $(seq 1 30); do
  echo "[deploy] build/install attempt ${i} for ${DEV}"
  xcodebuild -project TrackerCam.xcodeproj -scheme TrackerCam \
    -destination "platform=iOS,name=${DEV}" -allowProvisioningUpdates \
    -derivedDataPath .build-xcode build > /tmp/tc-deploy.log 2>&1
  if grep -q "BUILD SUCCEEDED" /tmp/tc-deploy.log; then ok=1; break; fi
  # Real signing/compile failures are fatal; everything else (device asleep/disconnected,
  # destination not found, transient account) is retried.
  if grep -qiE "requires a development team|No profiles for|CompileSwift failed|Swift Compiler Error|linker command failed" /tmp/tc-deploy.log; then
    echo "[deploy] FATAL:"; grep -iE "error:" /tmp/tc-deploy.log | grep -v AppIntents | head; exit 1
  fi
  echo "[deploy] not ready (device asleep/disconnected?) — retrying in 15s"
  sleep 15
done
[ "$ok" = 1 ] || { echo "[deploy] gave up after retries — ensure phone is unlocked + connected"; exit 1; }
echo "[deploy] BUILD SUCCEEDED"

DEVID="$(xcrun devicectl list devices 2>/dev/null | awk -F'  +' -v d="${DEV}" 'index($0,d){print $3; exit}')"
APP=".build-xcode/Build/Products/Debug-iphoneos/TrackerCam.app"
echo "[deploy] installing to ${DEVID}"
xcrun devicectl device install app --device "${DEVID}" "${APP}" 2>&1 | grep -iE "installationURL|error" | head
xcrun devicectl device process launch --device "${DEVID}" com.trackercam.app 2>&1 | grep -iE "launched|error|denied|locked|trust" | head
echo "[deploy] done"
