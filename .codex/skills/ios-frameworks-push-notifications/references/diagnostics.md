# Push Notification Diagnostics

Systematic troubleshooting for push notification failures.

## Failure Cause Distribution

| Cause | Frequency | Where to Check |
|---|---|---|
| Token/registration failures (never registered, wrong format, expired) | 30% | Step 2 |
| Entitlement/provisioning mismatch (capability missing, wrong environment) | 25% | Step 1 |
| Payload structure errors (missing keys, wrong types, invalid JSON) | 15% | Step 3 |
| Focus/interruption suppression (iOS 15+ filtering, provisional auth) | 15% | Step 4 |
| Service extension failures (timeout, crash, missing mutable-content) | 10% | Tree 4 |
| Delivery timing/throttling (silent push budget, APNs coalescing) | 5% | Tree 3 |

**Always verify entitlements and token registration BEFORE debugging payload or delivery logic.** 55% of failures are configuration, not code.

## Mandatory Diagnostic Steps

### Step 1: Verify Push Notification Entitlements

```bash
security cms -D -i path/to/embedded.mobileprovision | grep -A1 "aps-environment"
```

| Result | Meaning | Action |
|---|---|---|
| `<string>development</string>` | Entitlement present (sandbox) | Continue |
| `<string>production</string>` | Entitlement present (production) | Continue |
| No `aps-environment` key | Capability not enabled | Enable Push Notifications in Signing & Capabilities |

Find the provisioning profile:
```bash
find ~/Library/Developer/Xcode/DerivedData -name "embedded.mobileprovision" -newer . 2>/dev/null | head -3
```

### Step 2: Check Token Registration

```swift
func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    print("APNs token: \(token) (\(token.count) chars)")
}

func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
) {
    print("Registration failed: \(error.localizedDescription)")
}
```

| Result | Meaning | Action |
|---|---|---|
| 64-character hex token | Registration successful | Continue |
| "no valid aps-environment" | Capability misconfigured | Regenerate provisioning profile |
| Neither callback fires | `registerForRemoteNotifications()` never called | Call it after launch |
| Fails on Simulator | Expected | Test on physical device |

Both callbacks must be in `AppDelegate`, not `SceneDelegate`. SwiftUI apps need `@UIApplicationDelegateAdaptor`.

### Step 3: Validate Payload with curl

This proves whether the problem is client-side or server-side.

```bash
curl -v \
  --header "apns-topic: com.your.bundle.id" \
  --header "apns-push-type: alert" \
  --header "authorization: bearer $JWT_TOKEN" \
  --data '{"aps":{"alert":{"title":"Test","body":"Hello"}}}' \
  --http2 https://api.sandbox.push.apple.com/3/device/$DEVICE_TOKEN
```

| Response | Meaning | Action |
|---|---|---|
| HTTP/2 200 | Payload accepted | Problem is on-device (auth, Focus, extension) |
| 400 BadDeviceToken | Token format wrong or expired | Re-register |
| 403 ExpiredProviderToken | JWT older than 1 hour | Regenerate JWT |
| 403 InvalidProviderToken | Wrong key ID, team ID, or key | Check credentials |
| 410 Unregistered | App uninstalled or token invalidated | Remove from server |
| 413 PayloadTooLarge | Exceeds 4096 bytes | Reduce payload size |

### Step 4: Check Authorization Status

```swift
let settings = await UNUserNotificationCenter.current().notificationSettings()
print("Authorization: \(settings.authorizationStatus.rawValue)")
print("Alert: \(settings.alertSetting.rawValue)")
print("Sound: \(settings.soundSetting.rawValue)")
print("Badge: \(settings.badgeSetting.rawValue)")
```

| Raw Value | Status | Meaning |
|---|---|---|
| 0 | `.notDetermined` | Never requested |
| 1 | `.denied` | User denied or disabled in Settings |
| 2 | `.authorized` | User explicitly granted |
| 3 | `.provisional` | Quiet delivery, no prompt shown |
| 4 | `.ephemeral` | App Clip temporary |

## Decision Trees

### Tree 1: Not Receiving Any Notifications

```
Not receiving any notifications?
|
+-- Check Step 1 (entitlements)
|   +-- No aps-environment key?
|   |   --> Enable Push Notifications in Signing & Capabilities
|   +-- Present --> continue
|
+-- Check Step 2 (token registration)
|   +-- didFailToRegister called?
|   |   +-- "no valid aps-environment" --> Regenerate provisioning profile
|   |   +-- Other error --> Check network, use physical device
|   +-- Neither callback fires?
|   |   --> Verify registerForRemoteNotifications() called
|   +-- Token received --> continue
|
+-- Check Step 3 (payload delivery)
|   +-- HTTP 200 but no notification?
|   |   --> Check Step 4 (authorization status)
|   +-- 400 BadDeviceToken?
|   |   --> Re-register; check environment match
|   +-- 403/410 error?
|       --> Fix auth credentials or re-register
|
+-- Check Step 4 (user authorization)
    +-- Denied? --> Show Settings redirect
    +-- Not determined? --> Call requestAuthorization()
    +-- Authorized but still nothing?
        --> Check Focus mode, DND, notification grouping
```

### Tree 2: Works in Dev, Not Production

```
Works in development, fails in production?
|
+-- APNs endpoint correct?
|   +-- Dev: api.sandbox.push.apple.com
|   +-- Prod: api.push.apple.com
|       +-- Using sandbox endpoint with prod build? --> Switch
|
+-- Token environment matches?
|   +-- Dev and prod tokens are DIFFERENT
|   |   +-- Server storing dev token, sending to prod? --> Re-register
|   +-- Server distinguishes environments? --> Add environment flag
|
+-- Auth method correct?
|   +-- .p8 key? --> Same key works for both environments
|   +-- .p12 certificate?
|       +-- Dev cert only works with sandbox
|       +-- Prod cert only works with production
|
+-- Using FCM?
    +-- APNs auth key (.p8) uploaded to Firebase Console?
    |   --> Missing? Upload in Project Settings > Cloud Messaging
    +-- Team ID matches Apple Developer account?
```

### Tree 3: Silent Push Not Waking App

```
Silent push not waking app?
|
+-- Payload correct?
|   +-- Has "content-available": 1 in aps? --> Missing? Add it
|   +-- Has NO alert/badge/sound? --> Has alert? Not a silent push
|   +-- Valid --> continue
|
+-- Headers correct?
|   +-- apns-push-type: background? --> Must be "background"
|   +-- apns-priority: 5? --> Must be 5, not 10
|
+-- Background mode enabled?
|   +-- "Remote notifications" in Background Modes? --> Enable it
|   +-- didReceiveRemoteNotification handler implemented?
|
+-- App state?
|   +-- Force-quit by user? --> System will NOT wake it
|   +-- Suspended/background? --> Should wake, continue
|
+-- System throttling?
    +-- Budget: ~2-3 per hour --> Exceeding? Reduce frequency
    +-- Low Power Mode? --> Further reduces budget
```

### Tree 4: Rich Notification Missing Media

```
Rich notification not showing image/video?
|
+-- Payload has mutable-content: 1? --> Required for extension
|
+-- Service Extension target exists?
|   --> File > New > Target > Notification Service Extension
|
+-- Extension bundle ID correct?
|   +-- Must be: {app-bundle-id}.{extension-name}
|   +-- Wrong prefix? --> Fix to match parent app
|
+-- Download completing in time?
|   +-- Extension has ~30 seconds
|   +-- Large file? --> Use thumbnail, not full resolution
|   +-- serviceExtensionTimeWillExpire delivers fallback?
|
+-- Attachment type supported?
|   +-- Images: JPEG, GIF, PNG (max 10MB)
|   +-- Audio: AIFF, WAV, MP3, M4A (max 5MB)
|   +-- Video: MPEG, MP4 (max 50MB)
|
+-- App Groups configured?
    --> Extension and app need same App Group for shared data
```

### Tree 5: Live Activity Not Updating via Push

```
Live Activity not updating from push?
|
+-- APNs topic correct?
|   +-- Must be: {bundleID}.push-type.liveactivity
|   +-- Using plain bundle ID? --> Append suffix
|
+-- Push type header correct?
|   +-- apns-push-type: liveactivity --> Not "alert"
|
+-- content-state matches ActivityAttributes.ContentState?
|   +-- JSON keys match Swift property names exactly?
|   +-- Custom CodingKeys or encoding strategies?
|       --> NOT supported, use default key encoding
|
+-- Push token being sent to server?
|   +-- Observing activity.pushTokenUpdates?
|   +-- Handling token rotation on Activity restart?
|
+-- Rate limiting?
    +-- Updates: ~10-12 per hour per Activity
    +-- Alert updates (sound/vibration): ~3-4 per hour
```

### Tree 6: Notifications Stopped After iOS Update

```
Notifications stopped after iOS update?
|
+-- Focus mode auto-enabled? (iOS 15+)
|   +-- Check Settings > Focus
|   +-- App may not be in allowed list
|
+-- Interruption level filtering?
|   +-- Default .active is filtered by Focus
|   +-- Need Focus breakthrough? --> Use .timeSensitive
|   +-- .timeSensitive requires capability
|   +-- .critical requires Apple entitlement
|
+-- Provisional authorization behavior changed?
|   +-- iOS 15+ provisional appears in Summary only
|   +-- Relying on provisional? --> Request full authorization
|
+-- Communication notifications need INSendMessageIntent?
    +-- Missing? --> Donate intent before showing notification
    +-- Intent donated but filtered? --> Sender must be in contacts
```

## Push Notification Console Workflow

Apple's Push Notification Console provides server-free testing.

### Steps

1. Open https://icloud.developer.apple.com/dashboard
2. Select "Push Notifications" from sidebar
3. Choose your app's bundle ID
4. Enter device token, select environment (Sandbox/Production)
5. Compose payload or use template
6. Send and observe delivery status

### Check Delivery Logs

Copy `apns-id` from the response header of your push request. Use the console to look up delivery status by `apns-id`.

| Status | Meaning | Action |
|---|---|---|
| Delivered | APNs delivered to device | Problem is on-device |
| Dropped: Unregistered | Token invalid | Re-register device |
| Dropped: DeviceTokenNotForTopic | Bundle ID mismatch | Fix apns-topic header |
| Stored | Device offline | Wait or check connectivity |

## Simulator Push Testing

Simulators cannot register for remote notifications, but can test notification handling.

### Via simctl

```bash
cat > test-push.apns << 'EOF'
{
    "Simulator Target Bundle": "com.your.bundle.id",
    "aps": {
        "alert": {
            "title": "Test",
            "body": "Hello from simctl"
        },
        "sound": "default",
        "mutable-content": 1
    }
}
EOF

xcrun simctl push booted com.your.bundle.id test-push.apns
```

### Via Drag-and-Drop

Drag a `.apns` file directly onto the Simulator window. Requires `"Simulator Target Bundle"` key in the payload.

### Simulator Capabilities

| Feature | Supported |
|---|---|
| Notification appearance and content | Yes |
| Service Extension processing | Yes |
| Content Extension (custom UI) | Yes |
| Action handling and categories | Yes |
| APNs token registration | No |
| Silent push waking app | No |
| Live Activity push updates | No |

## APNs Response Code Reference

| Status | Meaning | Common Cause |
|---|---|---|
| 200 | Success | -- |
| 400 | Bad request | Malformed JSON, missing required header |
| 403 | Forbidden | Expired JWT, wrong team/key, topic mismatch |
| 404 | Not found | Invalid device token path |
| 405 | Method not allowed | Not using POST |
| 410 | Unregistered | App uninstalled, token invalidated |
| 413 | Payload too large | Exceeds 4KB (5KB for VoIP) |
| 429 | Too many requests | Rate limited by APNs |
| 500 | Internal server error | APNs issue, retry |
| 503 | Service unavailable | APNs overloaded, retry with backoff |

## FCM Diagnostics

### Swizzling Conflict

**Symptom:** Token callback not firing with Firebase.
**Cause:** Swizzling disabled but manual forwarding not implemented.

```swift
// If FirebaseAppDelegateProxyEnabled = NO, YOU must forward:
func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    Messaging.messaging().apnsToken = deviceToken
}
```

### Token Mismatch

**Symptom:** Server has FCM token but APNs delivery fails.
**Cause:** FCM token and APNs token are different. Send FCM token to your server, not the raw APNs token.

### Missing APNs Key

**Symptom:** FCM works on Android, not iOS.
**Fix:** Firebase Console -> Project Settings -> Cloud Messaging -> Upload APNs Authentication Key (.p8) with correct Key ID and Team ID.

## Anti-Rationalization Table

| Rationalization | Why It Fails | Time Cost |
|---|---|---|
| "It worked yesterday, entitlements are fine" | Provisioning profiles get regenerated during signing changes | 30-60 min debugging code when profile lost push capability |
| "Server says their payload is fine" | 55% of push failures are client-side. Verify independently with curl. | 1-2 hours of finger-pointing |
| "I'll skip token verification" | Wrong-environment tokens are the #1 cause of dev-vs-prod failures | 30+ min debugging valid payloads sent to invalid tokens |
| "Focus mode doesn't matter, we use default level" | Default `active` IS filtered by Focus | Hours adding code workarounds for a payload-level fix |
| "Silent push is reliable for sync" | Throttled ~2-3/hour, ignores force-quit apps | Architecture rework |
| "Service extension is set up" | Needs correct bundle ID, `mutable-content` in payload, AND completing in 30s | 30+ min when any prerequisite is missing |
| "FCM handles everything" | FCM wraps APNs. Token confusion, missing .p8, swizzling are APNs problems. | Hours debugging FCM for APNs config issues |
| "I'll test on Simulator first" | Simulator has no APNs token | Wasted test cycle |
| "Let me rewrite the notification handler" | 80% of failures are configuration, not code | Hours rewriting working code |
