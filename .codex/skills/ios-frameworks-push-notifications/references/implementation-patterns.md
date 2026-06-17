# Implementation Patterns

Notification patterns beyond basic setup: communication notifications, broadcast push, interruption level classification, silent push, relevance scores, and settings deep links.

## Communication Notifications (iOS 15+)

Show sender avatar and name. Can break through Focus for allowed contacts.

**Requirements:**
- Communication Notifications capability in Xcode
- Notification Service Extension target
- `mutable-content: 1` in payload

```swift
// In Notification Service Extension
import Intents

override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
) {
    guard let content = request.content.mutableCopy()
        as? UNMutableNotificationContent else {
        contentHandler(request.content)
        return
    }

    // 1. Create sender persona
    let sender = INPerson(
        personHandle: INPersonHandle(
            value: "alice@example.com",
            type: .emailAddress
        ),
        nameComponents: nil,
        displayName: "Alice",
        image: INImage(url: avatarURL),
        contactIdentifier: nil,
        customIdentifier: "user-alice-123"
    )

    // 2. Create message intent
    let intent = INSendMessageIntent(
        recipients: nil,       // nil for 1:1, set for group
        outgoingMessageType: .outgoingMessageText,
        content: content.body,
        speakableGroupName: nil,
        conversationIdentifier: "conversation-123",
        serviceName: nil,
        sender: sender,
        attachments: nil
    )

    // 3. Donate interaction
    let interaction = INInteraction(intent: intent, response: nil)
    interaction.direction = .incoming
    interaction.donate(completion: nil)

    // 4. Update content with intent
    do {
        let updatedContent = try content.updating(from: intent)
        contentHandler(updatedContent)
    } catch {
        contentHandler(content)
    }
}
```

Focus breakthrough: communication notifications from contacts the user has allowed in Focus settings break through. Overuse erodes trust -- users will disable the app entirely.

## Broadcast Push Channels (iOS 18+)

Channel-based delivery for large audiences (sports scores, flight status, breaking news). Only available for Live Activities.

### Subscribe to Channel

```swift
let activity = try Activity<ScoreAttributes>.request(
    attributes: attributes,
    content: initialContent,
    pushType: .channel(channelId)
)
```

### Server Sends to Channel

```
POST /4/broadcasts/apps/{TOPIC}
Headers:
  apns-push-type: liveactivity
  apns-channel-id: {channelID}
  authorization: bearer {JWT}
```

### Channel Rules

| Rule | Detail |
|---|---|
| Scope | Live Activities only, not regular push |
| Storage: No Storage | Deliver only to connected devices; higher budget |
| Storage: Most Recent | Store latest for offline devices; lower budget |
| Lifecycle | Delete unused channels; total active channels are limited |
| Identifiers | Opaque IDs, not user-facing names |

## Interruption Level Classification

Use the lowest level that matches the notification's urgency. Escalating everything to `time-sensitive` causes users to disable ALL notifications.

| Level | When to Use | Examples |
|---|---|---|
| `passive` | Informational, no urgency | Weekly digest, recommendations, social likes |
| `active` | Standard engagement, default | New message, comment reply, content update |
| `time-sensitive` | Genuinely time-bound events | Delivery arriving, meeting starting in 5 min, security alert |
| `critical` | Life/safety/security (Apple approval required) | Medical alert, severe weather, home security breach |

### Payload Examples

```json
// Passive -- silent delivery to Notification Center
{
    "aps": {
        "alert": { "title": "Weekly Digest", "body": "5 articles you might like" },
        "interruption-level": "passive"
    }
}

// Time Sensitive -- breaks scheduled summary
{
    "aps": {
        "alert": { "title": "Package Arriving", "body": "Your delivery is 2 stops away" },
        "interruption-level": "time-sensitive",
        "relevance-score": 0.9
    }
}
```

## Silent Push

Background content update without user-visible notification. Throttled to ~2-3 per hour.

### Requirements

- `content-available: 1` in aps dictionary
- No `alert`, `badge`, or `sound` keys
- `apns-push-type: background` header
- `apns-priority: 5` (MUST be 5, not 10)
- Background Modes capability with "Remote notifications" enabled
- App must NOT be force-quit by user

### Handler

```swift
func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
    // ~30 seconds of background execution
    Task {
        do {
            let hasNewData = try await performBackgroundSync()
            completionHandler(hasNewData ? .newData : .noData)
        } catch {
            completionHandler(.failed)
        }
    }
}
```

### Throttling Rules

| Condition | Budget |
|---|---|
| Normal | ~2-3 per hour |
| Low Power Mode | Further reduced |
| Force-quit by user | System will NOT wake app |
| Exceeding budget | Silently dropped, no error |

## Relevance Score

Ranks notifications in the notification summary (iOS 15+). Higher scores appear first.

```json
{
    "aps": {
        "alert": { "title": "Breaking News", "body": "..." },
        "relevance-score": 0.8,
        "thread-id": "news-breaking"
    }
}
```

- Range: 0.0 to 1.0
- `thread-id` groups notifications into conversations in Notification Center
- The highest-scored notification in a group represents the group in the summary

## Categories and Actions

### Register at Launch

```swift
func registerNotificationCategories() {
    let replyAction = UNTextInputNotificationAction(
        identifier: "REPLY",
        title: "Reply",
        options: []
    )

    let likeAction = UNNotificationAction(
        identifier: "LIKE",
        title: "Like",
        options: [],
        icon: UNNotificationActionIcon(systemImageName: "hand.thumbsup")
    )

    let messageCategory = UNNotificationCategory(
        identifier: "MESSAGE",
        actions: [replyAction, likeAction],
        intentIdentifiers: [],
        options: [.customDismissAction]
    )

    UNUserNotificationCenter.current()
        .setNotificationCategories([messageCategory])
}
```

### Handle Action Response

```swift
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
) async {
    let userInfo = response.notification.request.content.userInfo

    switch response.actionIdentifier {
    case "REPLY":
        if let text = (response as? UNTextInputNotificationResponse)?.userText {
            handleReply(text: text, userInfo: userInfo)
        }
    case "LIKE":
        handleLike(userInfo: userInfo)
    case UNNotificationDefaultActionIdentifier:
        handleNotificationTap(userInfo: userInfo)
    case UNNotificationDismissActionIdentifier:
        handleDismiss(userInfo: userInfo)
    default:
        break
    }
}
```

## Deep Link to Notification Settings

```swift
// iOS 16+: opens directly to your app's notification settings
if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
    UIApplication.shared.open(url)
}

// Fallback: general app settings
if let url = URL(string: UIApplication.openSettingsURLString) {
    UIApplication.shared.open(url)
}
```

## Live Activity Push Token Observation

```swift
let activity = try Activity<OrderAttributes>.request(
    attributes: attributes,
    content: initialContent,
    pushType: .token
)

Task {
    for await pushToken in activity.pushTokenUpdates {
        let token = pushToken.map { String(format: "%02x", $0) }.joined()
        try await sendPushToken(token)
    }
}
```

### Push-to-Start Token (iOS 17.2+)

```swift
for await token in Activity<OrderAttributes>.pushToStartTokenUpdates {
    let tokenString = token.map { String(format: "%02x", $0) }.joined()
    sendPushToStartTokenToServer(tokenString)
}
```

### Key Rules

- `content-state` must match `ActivityAttributes.ContentState` exactly -- no custom encoding strategies
- `timestamp` is required -- APNs uses it to discard stale updates
- Default `JSONDecoder` is always used; custom `CodingKeys` strategies are NOT supported
- Priority budget enforced -- excessive `apns-priority: 10` gets throttled
- Add `NSSupportsLiveActivitiesFrequentUpdates` to Info.plist for high-frequency apps
