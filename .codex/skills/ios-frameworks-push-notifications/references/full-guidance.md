# Push Notifications

Review and write iOS notification code for correctness, modern API usage, and production reliability.

## Responsibility

**Owns:** APNs registration, device token management, permission flows, payload design, notification categories/actions, service extensions, communication notifications (INSendMessageIntent), interruption levels, Live Activity push transport, broadcast push channels, local notification scheduling, FCM integration, foreground presentation.

**Does NOT own:** Live Activity UI/widgets (see extensions-widgets), background processing beyond silent push (see background-processing), server-side push infrastructure, authentication token storage (see ios-architecture).

## Core Principles

1. **Permission is a one-shot resource.** The system prompts only once. Request when the user understands the value, never at launch. ~60% of users who deny never re-enable in Settings.
2. **Tokens are ephemeral.** Never cache device tokens locally. They change after backup restore, device migration, reinstall, and OS updates. Call `registerForRemoteNotifications()` every launch and send the fresh token to your server.
3. **Sandbox and production are separate worlds.** Different APNs endpoints, different tokens. The same token sent to the wrong environment silently fails.
4. **Interruption levels are a trust budget.** Overusing `time-sensitive` causes users to disable ALL notifications. Reserve it for genuinely time-bound events.
5. **Service extensions must always deliver.** If neither `didReceive` nor `serviceExtensionTimeWillExpire` calls the content handler, the notification vanishes entirely.
6. **Silent push is a hint, not a guarantee.** Throttled to ~2-3/hour, ignored for force-quit apps. Never architect real-time sync around it.
7. **Test on physical devices.** Simulator cannot register for remote notifications and has no APNs token.

## Decision Tree

### What Type of Notification?

```
What type of notification?
|
+-- Alert (user-visible)
|   +-- Passive -- informational, no sound, appears in history
|   |   interruption-level: "passive"
|   |
|   +-- Active -- default, sound + banner
|   |   interruption-level: "active" (or omit, it's default)
|   |
|   +-- Time Sensitive -- breaks through scheduled summary, not Focus
|   |   interruption-level: "time-sensitive"
|   |   Requires: Time Sensitive Notifications capability
|   |
|   +-- Critical -- breaks through DND and mute switch
|       interruption-level: "critical"
|       Requires: Apple entitlement approval (medical, safety, security)
|
+-- Communication (iOS 15+)
|   Shows sender avatar, name; breaks Focus for allowed contacts
|   Requires: INSendMessageIntent + Communication Notifications capability
|   Configured in service extension via content.updating(from: intent)
|
+-- Silent / Background
|   content-available: 1, no alert/sound/badge
|   apns-push-type: background, apns-priority: 5 (MUST be 5)
|   Throttled ~2-3/hour, ~30s background execution
|   System will NOT wake force-quit apps
|
+-- Live Activity
    apns-push-type: liveactivity
    apns-topic: {bundleID}.push-type.liveactivity
    Updates/starts/ends Live Activities remotely
```

### Permission Timing

```
When to request notification permission?
|
+-- User just performed a value-revealing action?
|   (subscribed, scheduled reminder, enabled tracking)
|   +-- Yes --> Request now with contextual explanation
|   +-- No --> Don't request yet
|
+-- Need quiet trial delivery?
|   +-- Yes --> Use .provisional (no prompt, quiet delivery)
|   +-- No --> Use standard authorization
|
+-- User previously denied?
    +-- Yes --> Show in-app explanation + redirect to Settings
    +-- No, .notDetermined --> Request when context is right
```

## Red Flags

| Anti-Pattern | Problem | Fix | Time Cost |
|---|---|---|---|
| Permission request at app launch | ~60% permanent denial rate from reflexive "Don't Allow" | Request after user action that reveals notification value | Permanently lower opt-in rate |
| Caching device tokens in UserDefaults | Tokens change after restore/migration/reinstall; stale token = silent delivery failure | Send fresh token to server every launch | Hours debugging "notifications stopped" |
| Same token to sandbox AND production APNs | Tokens are per-environment; wrong endpoint = silent rejection | Server stores token + environment flag, uses matching APNs host | Hours debugging "works in dev, not prod" |
| `content-available: 1` as real-time sync | System throttles to ~2-3/hour, ignores force-quit apps | Use background URLSession or BackgroundTasks framework | Architecture rework |
| Missing `serviceExtensionTimeWillExpire` | Notification vanishes entirely if processing exceeds ~30s | Always deliver `bestAttemptContent` as fallback | Lost notifications in production |
| `apns-priority: 10` for all notifications | Drains battery, gets throttled by APNs | Use priority 10 only for time-sensitive alerts; 5 for everything else | Throttled delivery |
| Time Sensitive for everything | Users disable ALL notifications from your app; Apple can revoke capability | Classify by genuine urgency: passive/active/time-sensitive/critical | Eroded user trust |
| FCM with custom delegate + swizzling enabled | FCM swizzles delegate methods, conflicts with your handlers | Set `FirebaseAppDelegateProxyEnabled = NO`, forward tokens manually | Silent token registration failures |
| No foreground presentation delegate | Notifications received while app is active are silently dropped | Implement `willPresent` delegate method returning `[.banner, .sound, .badge]` | Missing notifications |
| Exceeding 4KB payload | APNs silently rejects oversized payloads, no error returned | Keep payload under 4KB; use `mutable-content` + service extension for media | Silent delivery failure |

## Mandatory First Steps

### 1. Enable Push Notification Capability

Xcode: Target -> Signing & Capabilities -> + Push Notifications. This adds the `aps-environment` entitlement. Verify in Apple Developer Portal that the App ID has Push Notifications enabled.

### 2. Register for Remote Notifications

```swift
// AppDelegate (or @UIApplicationDelegateAdaptor for SwiftUI)
func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    UIApplication.shared.registerForRemoteNotifications()
    return true
}

func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    sendTokenToServer(token) // Never cache locally
}

func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
) {
    // Simulator always fails here. Log, don't crash.
}
```

### 3. Request Authorization (In Context)

```swift
func subscribeToUpdates() async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()

    switch settings.authorizationStatus {
    case .notDetermined:
        let granted = try? await center.requestAuthorization(
            options: [.alert, .sound, .badge]
        )
        if granted == true {
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    case .authorized, .provisional:
        break // Already have permission
    case .denied:
        promptToOpenSettings()
    case .ephemeral:
        break
    @unknown default:
        break
    }
}
```

### 4. Handle Foreground Presentation

```swift
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
```

Without this, notifications received while the app is in foreground are silently dropped.

## Permission Patterns

### Provisional Authorization

Notifications appear quietly in Notification Center with Keep/Turn Off buttons. No permission dialog shown. Good for apps where users haven't yet discovered notification value.

```swift
let granted = try await center.requestAuthorization(
    options: [.alert, .sound, .badge, .provisional]
)
```

### Handling Denial (Redirect to Settings)

```swift
func promptToOpenSettings() {
    // iOS 16+: direct to notification settings
    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
        UIApplication.shared.open(url)
    } else if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
    }
}
```

## Token Management Rules

- **Never cache locally** -- request fresh at every app launch via `registerForRemoteNotifications()`
- **Sandbox != production** -- tokens differ per APNs environment
- **Server sync** -- send token + bundle ID + user ID + environment to your server
- **Tokens change** after backup restore, device migration, reinstall, OS updates

## FCM Integration

### Swizzling Trap

FCM swizzles `UNUserNotificationCenterDelegate` and `didRegisterForRemoteNotifications` by default. If you have custom delegate handling, they conflict.

**Fix**: Set in Info.plist:
```xml
<key>FirebaseAppDelegateProxyEnabled</key>
<false/>
```

Then forward the APNs token manually:
```swift
func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    Messaging.messaging().apnsToken = deviceToken
}
```

### Dual Token Confusion

FCM token != APNs device token. They are different values for different systems.

- FCM token -> your server (for sending via FCM)
- APNs token -> only needed if sending directly via APNs

### .p8 Key Upload

Upload your APNs authentication key (.p8) to Firebase Console -> Project Settings -> Cloud Messaging. Without this, development builds work (FCM uses sandbox automatically) but production builds silently fail.

## Pre-Ship Checklist

- [ ] Push Notifications capability added in Xcode
- [ ] Provisioning profile includes `aps-environment`
- [ ] Authorization requested in context, not at launch
- [ ] Denial handled gracefully (Settings redirect)
- [ ] Token sent to server every launch, never cached
- [ ] Server stores token per environment (sandbox/production)
- [ ] Foreground presentation delegate implemented
- [ ] Payload under 4KB (5KB for VoIP)
- [ ] Interruption level appropriate for content urgency
- [ ] Service extension implements `serviceExtensionTimeWillExpire` fallback
- [ ] Tested on physical device
- [ ] Tested both foreground and background delivery
- [ ] Category identifiers match between payload and registered categories

## References

- `references/implementation-patterns.md` -- Communication notifications, broadcast push, interruption level guidance, silent push, relevance scores, deep link to settings
- `references/diagnostics.md` -- Failure cause analysis, decision trees, curl validation, Push Notification Console, simulator testing, APNs response codes
- `references/apns-reference.md` -- HTTP/2 transport, JWT authentication, payload key table, local notification triggers, attachment limits, service extension patterns
