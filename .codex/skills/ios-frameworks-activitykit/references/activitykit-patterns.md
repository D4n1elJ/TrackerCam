# ActivityKit Patterns

## Setup

Info.plist:
- `NSSupportsLiveActivities` = YES
- `NSSupportsLiveActivitiesFrequentUpdates` = YES (optional, for frequent push updates)

## Defining Activity Attributes

```swift
import ActivityKit

struct DeliveryAttributes: ActivityAttributes {
    // Static data (doesn't change during activity)
    var orderNumber: String
    var restaurantName: String

    // Dynamic state (updates during activity)
    struct ContentState: Codable, Hashable {
        var status: String
        var estimatedArrival: Date
        var driverName: String
    }
}
```

## Starting a Live Activity

```swift
let attributes = DeliveryAttributes(orderNumber: "1234", restaurantName: "Pizza Place")

let initialState = DeliveryAttributes.ContentState(
    status: "Preparing",
    estimatedArrival: Date().addingTimeInterval(1800),
    driverName: "Alex"
)

let content = ActivityContent(state: initialState, staleDate: Date().addingTimeInterval(3600))

let activity = try Activity.request(
    attributes: attributes,
    content: content,
    pushType: .token  // Enable push updates (nil for local-only)
)
```

## Updating a Live Activity

```swift
// From app
let updatedState = DeliveryAttributes.ContentState(
    status: "On the way",
    estimatedArrival: Date().addingTimeInterval(900),
    driverName: "Alex"
)

let alertConfig = AlertConfiguration(
    title: "Order Update",
    body: "Your order is on the way!",
    sound: .default
)

await activity.update(
    ActivityContent(state: updatedState, staleDate: Date().addingTimeInterval(1800)),
    alertConfiguration: alertConfig  // Optional — triggers notification
)
```

## Ending a Live Activity

```swift
let finalState = DeliveryAttributes.ContentState(
    status: "Delivered",
    estimatedArrival: Date(),
    driverName: "Alex"
)

await activity.end(
    ActivityContent(state: finalState, staleDate: nil),
    dismissalPolicy: .default  // .immediate or .after(Date())
)
```

## Observing Activities

```swift
// All activities for this type
for activity in Activity<DeliveryAttributes>.activities {
    print(activity.id, activity.content.state.status)
}

// Activity updates
Task {
    for await content in activity.contentUpdates {
        print(content.state.status)
    }
}

// Activity state changes
Task {
    for await state in activity.activityStateUpdates {
        switch state {
        case .active: break
        case .ended: break
        case .dismissed: break
        case .stale: break  // Past stale date
        @unknown default: break
        }
    }
}
```

## Push Token Management

```swift
// Observe token for this activity
Task {
    for await tokenData in activity.pushTokenUpdates {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        // Send token to your server
        await sendTokenToServer(token, activityID: activity.id)
    }
}
```

## Widget Extension — Live Activity UI

```swift
import WidgetKit
import SwiftUI

struct DeliveryLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeliveryAttributes.self) { context in
            // Lock Screen / banner presentation
            VStack {
                Text(context.attributes.restaurantName).font(.headline)
                Text(context.state.status)
                Text(context.state.estimatedArrival, style: .timer)
            }
            .padding()

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded presentation
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "bag.fill")
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.status).font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.estimatedArrival, style: .timer)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Driver: \(context.state.driverName)")
                }
            } compactLeading: {
                Image(systemName: "bag.fill")
            } compactTrailing: {
                Text(context.state.estimatedArrival, style: .timer)
            } minimal: {
                Image(systemName: "bag.fill")
            }
        }
    }
}
```

## Constraints

- Max 8 hours active (12 with stale date, then system ends it)
- Content state must encode to < 4KB (push)
- Max ~5 concurrent Live Activities per device
- UI rendered by widget extension (same constraints as widgets)
- No network requests, no async loading in widget views
- visionOS does not support Live Activities
