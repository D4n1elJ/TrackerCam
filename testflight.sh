#!/usr/bin/env bash
# Archive, export, and upload TrackerCam to TestFlight / App Store Connect.
#
# Prerequisites (one-time, see improvements2.md E1):
#   - Paid Apple Developer Program membership for team DZNC8GD6WJ.
#   - An app record for com.trackercam.app in App Store Connect.
#   - An App Store Connect API key (.p8) + its Key ID and Issuer ID.
#
# Auth via App Store Connect API key (recommended). Provide either env vars or ~/.appstoreconnect:
#   ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-... ASC_KEY_PATH=/path/AuthKey_XXXX.p8 ./testflight.sh
#
# Each upload needs a unique, increasing build number. Pass BUMP=1 to auto-increment
# CURRENT_PROJECT_VERSION in project.yml before archiving.
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")"

PROJECT="TrackerCam.xcodeproj"
SCHEME="TrackerCam"
ARCHIVE_PATH=".build-xcode/TrackerCam.xcarchive"
EXPORT_DIR=".build-xcode/export"

# --- Optional build-number bump ---------------------------------------------------------------
if [[ "${BUMP:-0}" == "1" ]]; then
  cur=$(grep -E 'CURRENT_PROJECT_VERSION:' project.yml | grep -oE '[0-9]+' | head -1)
  next=$((cur + 1))
  /usr/bin/sed -i '' "s/CURRENT_PROJECT_VERSION: \"${cur}\"/CURRENT_PROJECT_VERSION: \"${next}\"/" project.yml
  echo "[testflight] bumped build ${cur} -> ${next}"
fi

# --- Regenerate + archive (Release) -----------------------------------------------------------
echo "[testflight] regenerating project"
xcodegen generate

echo "[testflight] archiving (Release, generic iOS)"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates archive

# --- Export the .ipa --------------------------------------------------------------------------
echo "[testflight] exporting .ipa"
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates

IPA=$(/usr/bin/find "$EXPORT_DIR" -name '*.ipa' | head -1)
[[ -n "$IPA" ]] || { echo "[testflight] no .ipa produced"; exit 1; }
echo "[testflight] built: $IPA"

# --- Upload to App Store Connect --------------------------------------------------------------
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]]; then
  echo "[testflight] uploading via App Store Connect API key"
  # altool reads the key from ./private_keys, ~/private_keys, or ~/.appstoreconnect/private_keys.
  mkdir -p ~/.appstoreconnect/private_keys
  cp "$ASC_KEY_PATH" ~/.appstoreconnect/private_keys/ 2>/dev/null || true
  xcrun altool --upload-app -f "$IPA" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  echo "[testflight] uploaded. It will appear in TestFlight after processing (~5–30 min)."
else
  cat <<'NOTE'
[testflight] .ipa is built but NOT uploaded — no App Store Connect API key provided.
  Set ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH and re-run, or upload the .ipa manually via
  Xcode Organizer ("Distribute App") or Transporter.
NOTE
fi
