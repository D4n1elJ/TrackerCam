# Getting TrackerCam onto TestFlight

The **code side is done** — flattened icon, `ITSAppUsesNonExemptEncryption=false`, and
`testflight.sh` + `ExportOptions.plist`. What remains is account setup (only you can do these) and
running one command.

## 1. Confirm the Apple Developer Program is active  (~5 min)
- Sign in at <https://developer.apple.com/account>. Confirm membership is **active** (paid, $99/yr)
  for team **`DZNC8GD6WJ`** (the team in `project.yml`). Development signing working is *not* proof —
  TestFlight needs paid enrollment.
- If not enrolled: enroll and wait for activation before continuing.

## 2. Create the app record in App Store Connect  (~5 min)
- Go to <https://appstoreconnect.apple.com> → **Apps → +  → New App**.
- Platform: iOS · Name: TrackerCam · Primary language: English · **Bundle ID:
  `com.trackercam.app`** (pick it from the list — if it's not there, register it first under
  *Certificates, Identifiers & Profiles → Identifiers* as an explicit App ID) · SKU: `trackercam` (any
  unique string).
- This registers the app so a build has somewhere to land.

## 3. Create an App Store Connect API key  (~3 min)
- App Store Connect → **Users and Access → Integrations → App Store Connect API → +**.
- Access: **App Manager** (or Admin). Name it e.g. `trackercam-upload`.
- Download the **`AuthKey_XXXXXXXXXX.p8`** (you can only download it once — keep it safe).
- Note the **Key ID** (the `XXXXXXXXXX`) and the **Issuer ID** (shown at the top of the Keys page).

## 4. Upload a build  (~10 min + processing)
From the repo root:

```sh
ASC_KEY_ID=XXXXXXXXXX \
ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
ASC_KEY_PATH=/path/to/AuthKey_XXXXXXXXXX.p8 \
BUMP=1 ./testflight.sh
```

What it does: regenerate the project → archive Release → export an `.ipa` with
`ExportOptions.plist` → upload via the API key. `BUMP=1` bumps `CURRENT_PROJECT_VERSION` first (each
upload needs a unique, increasing build number).

If you'd rather upload manually, drop the `ASC_*` vars — the script still builds the `.ipa` and tells
you to upload it via **Xcode → Organizer → Distribute App** or the **Transporter** app.

## 5. Add testers  (after processing, ~5–30 min)
- App Store Connect → your app → **TestFlight**.
- **Internal testers** (up to 100, App Store Connect users): available immediately after processing,
  **no review**. Easiest for your own devices.
- **External testers** (public link / email): require a one-time **Beta App Review** and a filled-in
  "Test Information" section (beta description, contact email, and the encryption answer — already
  satisfied by `ITSAppUsesNonExemptEncryption`).

## Troubleshooting
- *"No account for team DZNC8GD6WJ"* → step 1 (membership) or sign in to that team in Xcode.
- *"No profiles for com.trackercam.app"* → the App ID isn't registered (step 2) or signing needs
  `-allowProvisioningUpdates` (already in `testflight.sh`).
- *"Redundant binary upload / build already exists"* → bump the build number (`BUMP=1`).
- *Invalid icon / alpha* → already fixed (icon flattened).
