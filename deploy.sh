#!/usr/bin/env bash
# Rebuild TrackerCam and (re)install it to the connected/networked iPhone.
# Trust persists across updates; requires the phone unlocked, Developer Mode on, same LAN or cable.
#
#   ./deploy.sh
#   DEVICE="Daniels Phone" ./deploy.sh
set -uo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$(dirname "$0")"
DEV="${DEVICE:-Daniels Phone}"

echo "[deploy] building for ${DEV}"
xcodebuild -project TrackerCam.xcodeproj -scheme TrackerCam \
  -destination "platform=iOS,name=${DEV}" -allowProvisioningUpdates \
  -derivedDataPath .build-xcode build > /tmp/tc-deploy.log 2>&1
if ! grep -q "BUILD SUCCEEDED" /tmp/tc-deploy.log; then
  echo "[deploy] BUILD FAILED:"; grep -iE "error:" /tmp/tc-deploy.log | grep -v AppIntents | head
  exit 1
fi
echo "[deploy] BUILD SUCCEEDED"

DEVID="$(xcrun devicectl list devices 2>/dev/null | awk -F'  +' -v d="${DEV}" 'index($0,d){print $3; exit}')"
APP=".build-xcode/Build/Products/Debug-iphoneos/TrackerCam.app"
echo "[deploy] installing to ${DEVID}"
xcrun devicectl device install app --device "${DEVID}" "${APP}" 2>&1 | grep -iE "installationURL|error" | head
echo "[deploy] launching"
xcrun devicectl device process launch --device "${DEVID}" com.trackercam.app 2>&1 | grep -iE "launched|error|denied|trust" | head
echo "[deploy] done"
