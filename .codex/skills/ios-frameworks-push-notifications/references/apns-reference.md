# APNs Reference

Complete API reference for APNs HTTP/2 transport, JWT authentication, payload structure, local notification triggers, attachment limits, and service extension lifecycle.

## APNs HTTP/2 Transport

### Endpoints

| Environment | Host | Port |
|---|---|---|
| Development (sandbox) | api.sandbox.push.apple.com | 443 or 2197 |
| Production | api.push.apple.com | 443 or 2197 |

### Request Format

```
POST /3/device/{device_token}
Host: api.push.apple.com
Authorization: bearer {jwt_token}
apns-topic: {bundle_id}
apns-push-type: alert
Content-Type: application/json

{"aps":{"alert":{"title":"Hello","body":"World"}}}
```

### Request Headers

| Header | Required | Values | Notes |
|---|---|---|---|
| apns-push-type | Yes | alert, background, liveactivity, voip, complication, fileprovider, mdm, location | Must match payload content |
| apns-topic | Yes | Bundle ID (or with `.push-type.liveactivity` suffix) | Required for token-based auth |
| apns-priority | No | 10 (immediate), 5 (power-conscious), 1 (low) | Default: 10 for alert, 5 for background |
| apns-expiration | No | UNIX timestamp or 0 | 0 = deliver once, don't store |
| apns-collapse-id | No | String (max 64 bytes) | Replaces matching notification on device |
| apns-id | No | UUID (lowercase) | Returned by APNs for tracking |
| authorization | Token auth | bearer {JWT} | Not needed for certificate auth |
| apns-unique-id | Response only | UUID | Use with Push Notification Console delivery log |

### Response Codes

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

### Payload Size Limits

| Type | Max Size |
|---|---|
| Standard push | 4 KB |
| VoIP push | 5 KB |
| Live Activity | 4 KB |

APNs silently rejects oversized payloads. No error returned to sender.

## JWT Authentication

### Structure

**Header:**
```json
{ "alg": "ES256", "kid": "{10-char Key ID}" }
```

**Claims:**
```json
{ "iss": "{10-char Team ID}", "iat": {unix_timestamp} }
```

### Rules

| Rule | Detail |
|---|---|
| Algorithm | ES256 (P-256 curve) |
| Signing key | APNs auth key (.p8 from Apple Developer Portal) |
| Token lifetime | Max 1 hour (403 ExpiredProviderToken if older) |
| Refresh interval | Between 20 and 60 minutes |
| Scope | One key works for all apps in team, both environments |

### Bash JWT Generation Script

```bash
#!/bin/bash
# Generate APNs JWT for curl testing
# Requires: AUTH_KEY_ID, TEAM_ID, TOKEN_KEY_FILE_NAME (path to .p8)

JWT_ISSUE_TIME=$(date +%s)

JWT_HEADER=$(printf '{ "alg": "ES256", "kid": "%s" }' "${AUTH_KEY_ID}" \
    | openssl base64 -e -A | tr -- '+/' '-_' | tr -d =)

JWT_CLAIMS=$(printf '{ "iss": "%s", "iat": %d }' "${TEAM_ID}" "${JWT_ISSUE_TIME}" \
    | openssl base64 -e -A | tr -- '+/' '-_' | tr -d =)

JWT_HEADER_CLAIMS="${JWT_HEADER}.${JWT_CLAIMS}"

JWT_SIGNED=$(printf "${JWT_HEADER_CLAIMS}" \
    | openssl dgst -binary -sha256 -sign "${TOKEN_KEY_FILE_NAME}" \
    | openssl base64 -e -A | tr -- '+/' '-_' | tr -d =)

AUTHENTICATION_TOKEN="${JWT_HEADER}.${JWT_CLAIMS}.${JWT_SIGNED}"
echo "${AUTHENTICATION_TOKEN}"
```

### Send Test Push with Generated JWT

```bash
curl -v \
    --header "apns-topic: $BUNDLE_ID" \
    --header "apns-push-type: alert" \
    --header "authorization: bearer $AUTHENTICATION_TOKEN" \
    --data '{"aps":{"alert":{"title":"Test","body":"Hello"}}}' \
    --http2 https://api.sandbox.push.apple.com/3/device/$DEVICE_TOKEN
```

## `aps` Dictionary Key Table

| Key | Type | Purpose | Since |
|---|---|---|---|
| alert | Dict or String | Alert content (title, subtitle, body) | iOS 10 |
| badge | Number | App icon badge count (0 removes) | iOS 10 |
| sound | String or Dict | Audio playback ("default" or custom filename) | iOS 10 |
| thread-id | String | Notification grouping in Notification Center | iOS 10 |
| category | String | Actionable notification type identifier | iOS 10 |
| content-available | Number (1) | Silent background push trigger | iOS 10 |
| mutable-content | Number (1) | Triggers Notification Service Extension | iOS 10 |
| target-content-id | String | Window or content identifier | iOS 13 |
| interruption-level | String | passive, active, time-sensitive, critical | iOS 15 |
| relevance-score | Number (0.0-1.0) | Notification summary sorting priority | iOS 15 |
| filter-criteria | String | Focus filter matching | iOS 15 |
| stale-date | Number | UNIX timestamp, Live Activity staleness indicator | iOS 16.1 |
| content-state | Dict | Live Activity content update payload | iOS 16.1 |
| timestamp | Number | UNIX timestamp, required for Live Activity | iOS 16.1 |
| event | String | start, update, end (Live Activity lifecycle) | iOS 16.1 |
| dismissal-date | Number | UNIX timestamp, when ended activity disappears | iOS 16.1 |
| attributes-type | String | Live Activity struct name for push-to-start | iOS 17 |
| attributes | Dict | Live Activity initialization data | iOS 17 |

### Alert Dictionary Keys

| Key | Type | Purpose |
|---|---|---|
| title | String | Short title |
| subtitle | String | Secondary description |
| body | String | Full message text |
| launch-image | String | Launch screen filename |
| title-loc-key | String | Localization key for title |
| title-loc-args | [String] | Title format arguments |
| subtitle-loc-key | String | Localization key for subtitle |
| subtitle-loc-args | [String] | Subtitle format arguments |
| loc-key | String | Localization key for body |
| loc-args | [String] | Body format arguments |

### Sound Dictionary (Critical Alerts)

```json
{ "critical": 1, "name": "alarm.aiff", "volume": 0.8 }
```

Requires Apple-approved Critical Alerts entitlement (medical, safety, security apps only).

### Interruption Level Values

| Value | Behavior | Requires |
|---|---|---|
| passive | No sound, no screen wake, summary only | Nothing |
| active | Default behavior, sound + banner | Nothing |
| time-sensitive | Breaks scheduled delivery, banner persists | Time Sensitive capability |
| critical | Overrides DND and ringer switch | Apple approval + entitlement |

## Local Notification Triggers

### Trigger Comparison

| Trigger | Use Case | Repeating | Min Interval |
|---|---|---|---|
| UNTimeIntervalNotificationTrigger | After N seconds | Yes | 60 seconds |
| UNCalendarNotificationTrigger | Specific date/time | Yes | -- |
| UNLocationNotificationTrigger | Enter/exit region | Yes | -- |

### Time Interval

```swift
let trigger = UNTimeIntervalNotificationTrigger(
    timeInterval: 300,
    repeats: false
)
```

### Calendar

```swift
var components = DateComponents()
components.hour = 9
components.minute = 0
let trigger = UNCalendarNotificationTrigger(
    dateMatching: components,
    repeats: true
)
```

### Location

```swift
import CoreLocation

let center = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
let region = CLCircularRegion(center: center, radius: 100, identifier: "office")
region.notifyOnEntry = true
region.notifyOnExit = false
let trigger = UNLocationNotificationTrigger(region: region, repeats: false)
```

### Schedule a Local Notification

```swift
let content = UNMutableNotificationContent()
content.title = "Reminder"
content.body = "Time to take a break"
content.sound = .default

let request = UNNotificationRequest(
    identifier: "break-reminder",
    content: content,
    trigger: trigger
)

try await UNUserNotificationCenter.current().add(request)
```

### Local Notification Limitations

| Limitation | Detail |
|---|---|
| Pending limit | 64 pending requests per app |
| Min repeat interval | 60 seconds for time-interval triggers |
| Location auth | Requires When In Use or Always location authorization |
| No service extensions | Local notifications do not trigger UNNotificationServiceExtension |
| No background wake | Cannot use `content-available` for background processing |
| App extensions | Cannot schedule from app extensions; use App Group + main app |

## Attachment Types and Size Limits

| Type | Extensions | Max Size |
|---|---|---|
| Image | .jpg, .gif, .png | 10 MB |
| Audio | .aif, .wav, .mp3 | 5 MB |
| Video | .mp4, .mpeg | 50 MB |

Payload must include `"mutable-content": 1` for the service extension to fire and download attachments.

## Service Extension Lifecycle

| Method | Time Window | Purpose |
|---|---|---|
| `didReceive(_:withContentHandler:)` | ~30 seconds | Modify notification content (download media, decrypt, etc.) |
| `serviceExtensionTimeWillExpire()` | Called at deadline | Deliver best-attempt content immediately |

### Media Enrichment Pattern

```swift
class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = request.content.mutableCopy()
            as? UNMutableNotificationContent

        guard let content = bestAttemptContent,
              let imageURLString = content.userInfo["image-url"] as? String,
              let imageURL = URL(string: imageURLString) else {
            contentHandler(request.content)
            return
        }

        let task = URLSession.shared.downloadTask(with: imageURL) {
            [weak self] url, _, error in
            guard let self, let url, error == nil else {
                contentHandler(self?.bestAttemptContent ?? request.content)
                return
            }

            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")
            try? FileManager.default.moveItem(at: url, to: tmpURL)

            if let attachment = try? UNNotificationAttachment(
                identifier: "image", url: tmpURL, options: nil
            ) {
                content.attachments = [attachment]
            }
            contentHandler(content)
        }
        task.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        // Deliver whatever we have -- text without image beats nothing
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}
```

### End-to-End Decryption Pattern

```swift
override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
) {
    self.contentHandler = contentHandler
    bestAttemptContent = request.content.mutableCopy()
        as? UNMutableNotificationContent

    guard let content = bestAttemptContent,
          let encrypted = content.userInfo["encryptedBody"] as? String else {
        contentHandler(request.content)
        return
    }

    content.body = decrypt(encrypted) ?? "(Encrypted message)"
    contentHandler(content)
}

override func serviceExtensionTimeWillExpire() {
    if let contentHandler, let bestAttemptContent {
        bestAttemptContent.body = "(Encrypted message)"
        contentHandler(bestAttemptContent)
    }
}
```

## UNUserNotificationCenter Key Methods

| Method | Purpose |
|---|---|
| `requestAuthorization(options:)` | Request permission |
| `notificationSettings()` | Check current status |
| `add(_:)` | Schedule notification request |
| `getPendingNotificationRequests()` | List scheduled notifications |
| `removePendingNotificationRequests(withIdentifiers:)` | Cancel scheduled |
| `getDeliveredNotifications()` | List in notification center |
| `removeDeliveredNotifications(withIdentifiers:)` | Remove from center |
| `setNotificationCategories(_:)` | Register actionable types |
| `setBadgeCount(_:)` | Update badge (iOS 16+) |

## UNAuthorizationOptions

| Option | Purpose |
|---|---|
| .alert | Display alerts |
| .badge | Update badge count |
| .sound | Play sounds |
| .carPlay | Show in CarPlay |
| .criticalAlert | Critical alerts (requires entitlement) |
| .provisional | Trial delivery without prompting |
| .providesAppNotificationSettings | "Configure in App" button in Settings |

## Live Activity Push Headers

| Header | Value |
|---|---|
| apns-push-type | liveactivity |
| apns-topic | {bundleID}.push-type.liveactivity |
| apns-priority | 5 (routine) or 10 (time-sensitive) |

### Event Types

| Event | Purpose | Required Fields |
|---|---|---|
| start | Start Live Activity remotely (iOS 17.2+) | attributes-type, attributes, content-state, timestamp |
| update | Update content-state | content-state, timestamp |
| end | End the activity | timestamp (content-state optional) |
