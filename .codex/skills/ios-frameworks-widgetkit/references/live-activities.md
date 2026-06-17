# Live Activities

## ActivityAttributes

Static data (set at start, never changes) plus a `ContentState` inner type (updated throughout lifecycle).

```swift
import ActivityKit

struct DeliveryAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: DeliveryStatus
        var estimatedArrival: Date
        var driverName: String?
    }

    var orderNumber: String
    var restaurantName: String
}
```

### 4 KB Size Limit

`ActivityAttributes` + `ContentState` combined must be under 4096 bytes. Exceeding this causes `Activity.request()` to throw silently.

**Size checking code:**

```swift
func checkActivitySize<T: ActivityAttributes>(
    attributes: T,
    state: T.ContentState
) where T.ContentState: Encodable {
    let encoder = JSONEncoder()
    guard let attrData = try? encoder.encode(attributes),
          let stateData = try? encoder.encode(state) else {
        print("Failed to encode — check Codable conformance")
        return
    }
    let total = attrData.count + stateData.count
    switch total {
    case ..<2048:
        print("Size: \(total) bytes — safe with room to grow")
    case 2048..<3072:
        print("Size: \(total) bytes — acceptable, monitor as you add fields")
    case 3072..<3584:
        print("Size: \(total) bytes — risky, optimise now")
    default:
        print("Size: \(total) bytes — CRITICAL, will likely fail at 4096")
    }
}
```

**Optimization when over budget:**
1. Replace `String` descriptions with enums (fixed sets)
2. Shorten string values
3. Use smaller numeric types (`Int8` if range allows)
4. Remove rarely-used optional fields
5. Store IDs/references, not full objects
6. Use asset catalog names for images, never raw `Data`

## Starting a Live Activity

```swift
let attributes = DeliveryAttributes(orderNumber: "12345", restaurantName: "Pizza Place")
let initialState = DeliveryAttributes.ContentState(
    status: .preparing,
    estimatedArrival: Date().addingTimeInterval(30 * 60)
)

// Check authorization first
guard ActivityAuthorizationInfo().areActivitiesEnabled else {
    // Handle — user has disabled Live Activities in Settings
    return
}

let activity = try Activity.request(
    attributes: attributes,
    content: ActivityContent(state: initialState, staleDate: nil),
    pushType: nil  // nil = local updates only, .token = push
)

// Store activity.id for later updates
```

**Common errors from `Activity.request()`:**
- `ActivityAuthorizationError` — User denied permission
- `ActivityError.dataTooLarge` — Over 4 KB
- `ActivityError.tooManyActivities` — System limit (typically 2-3 simultaneous)

## Updating a Live Activity

```swift
guard let activity = Activity<DeliveryAttributes>.activities
    .first(where: { $0.id == storedActivityID }) else { return }

let updatedState = DeliveryAttributes.ContentState(
    status: .onTheWay,
    estimatedArrival: Date().addingTimeInterval(10 * 60),
    driverName: "Alex"
)

await activity.update(
    ActivityContent(state: updatedState, staleDate: Date().addingTimeInterval(120))
)

// With alert:
await activity.update(
    ActivityContent(state: updatedState, staleDate: nil),
    alertConfiguration: AlertConfiguration(
        title: "Order Update",
        body: "Your delivery is on the way",
        sound: .default
    )
)
```

## Dynamic Island Layout

Three presentation sizes, all defined in a single `DynamicIsland` builder.

### Compact (leading + trailing)

Shown when one activity is active. Two small areas flanking the TrueDepth camera.

### Minimal

Shown when multiple activities are active. Single circular element attached to the island.

### Expanded

Shown when user long-presses the compact view. Four regions: leading, trailing, center, bottom.

```swift
DynamicIsland {
    // Expanded regions
    DynamicIslandExpandedRegion(.leading) {
        Image(systemName: "box.truck")
            .font(.title2)
    }
    DynamicIslandExpandedRegion(.trailing) {
        VStack(alignment: .trailing) {
            Text(context.state.estimatedArrival, style: .timer)
                .font(.title2.monospacedDigit())
            Text("remaining")
                .font(.caption2)
        }
    }
    DynamicIslandExpandedRegion(.bottom) {
        HStack {
            Button(intent: ContactDriverIntent()) {
                Label("Contact", systemImage: "phone.fill")
            }
        }
    }
} compactLeading: {
    Image(systemName: "box.truck")
} compactTrailing: {
    Text(context.state.estimatedArrival, style: .timer)
        .frame(width: 44)
} minimal: {
    Image(systemName: "box.truck")
        .foregroundStyle(.tint)
}
```

**Design rules:**
- Content should nest concentrically inside the island's rounded shape with even margins
- Use `.spring(response: 0.6, dampingFraction: 0.7)` for organic animations, not linear
- Never use sharp `Rectangle()` — it pokes into corners

## Dismissal Policies (Zombie Activity Prevention)

Every activity MUST call `.end()` when the event completes. Activities without explicit dismissal persist indefinitely on the Lock Screen.

```swift
// Default — stays on Lock Screen ~4 hours showing final state, then removed
await activity.end(
    ActivityContent(state: finalState, staleDate: nil),
    dismissalPolicy: .default
)

// Immediate — removed right away (timers completed, songs finished)
await activity.end(nil, dismissalPolicy: .immediate)

// Timed — removed at specific date (meeting ends, flight lands)
await activity.end(nil, dismissalPolicy: .after(Date().addingTimeInterval(30 * 60)))
```

**Choose based on event type:**
- `.immediate` — Transient events with no useful "completed" state
- `.default` — Most activities (delivery complete, game over — user may want to glance at result)
- `.after(date)` — Known end time

## Local Updates vs Push Updates

### Local Updates (Ship First)

No entitlement required. Updates happen when the app is running.

```swift
let activity = try Activity.request(
    attributes: attributes,
    content: initialContent,
    pushType: nil  // Local only
)

// Update from anywhere in the app:
await activity.update(ActivityContent(state: newState, staleDate: nil))
```

**Limitation:** Updates only arrive when the user has the app open or the app has background execution time.

### Push Updates (Ship After Entitlement)

Requires `com.apple.developer.activity-push-notification` entitlement. Approval takes 3-7 days.

```swift
let activity = try Activity.request(
    attributes: attributes,
    content: initialContent,
    pushType: .token
)

// Monitor for push token
Task {
    for await pushToken in activity.pushTokenUpdates {
        let tokenString = pushToken.map { String(format: "%02x", $0) }.joined()
        await sendTokenToServer(activityID: activity.id, token: tokenString)
    }
}
```

**Server push payload:**

```json
{
  "aps": {
    "timestamp": 1633046400,
    "event": "update",
    "content-state": {
      "status": "onTheWay",
      "estimatedArrival": "2024-01-15T18:30:00Z",
      "driverName": "Alex"
    }
  }
}
```

**Standard push limit:** ~10-12 per hour.

### Frequent Updates (iOS 18.2+)

For live events (sports, stocks), request the `NSSupportsLiveActivitiesFrequentUpdates` entitlement for higher push rate limits. Requires justification in App Store Connect.

```xml
<!-- Info.plist -->
<key>NSSupportsLiveActivitiesFrequentUpdates</key>
<true/>
```

## Phased Shipping Approach

1. **Week 1:** Ship with `pushType: nil` (local updates). Updates arrive when the user opens the app. Acceptable for v1.0.
2. **Week 1:** Apply for push notification entitlement. Approval takes 3-7 days.
3. **Week 2:** Ship update with `pushType: .token`. Wire server push infrastructure. Updates arrive in 1-3 seconds.
4. **If needed:** Apply for frequent updates entitlement with justification.

Never promise push-based "real-time" features before entitlement approval.

## Broadcast Push Channels (iOS 18.2+)

For one-to-many Live Activity updates (sports scores going to all users watching the same game).

Instead of sending individual pushes per device, register a channel token:

```swift
let activity = try Activity.request(
    attributes: attributes,
    content: initialContent,
    pushType: .token
)

// Subscribe to broadcast channel
for await channelToken in activity.pushTokenUpdates {
    // Server sends one push to channel, all subscribed devices receive it
    await registerForBroadcast(channel: "game-\(gameID)", token: channelToken)
}
```

Server sends a single push to the channel endpoint. All subscribed devices receive the update. Reduces server fan-out from N pushes to 1.

## watchOS Live Activities

Add `.supplementalActivityFamilies([.small])` to `ActivityConfiguration` to show on Apple Watch Smart Stack (watchOS 11+).

```swift
@Environment(\.activityFamily) var activityFamily

var body: some View {
    if activityFamily == .small {
        // Compact watch layout
        WatchActivityView(state: context.state)
    } else {
        // Full iPhone layout
        PhoneActivityView(state: context.state)
    }
}
```

Use `@Environment(\.isLuminanceReduced)` to simplify views for Always On Display — reduce detail, use white text, larger fonts.
