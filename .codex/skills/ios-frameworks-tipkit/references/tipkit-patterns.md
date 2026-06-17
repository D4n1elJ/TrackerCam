# TipKit Patterns

## Configuration

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    try? Tips.configure([
                        .displayFrequency(.daily),        // Max one tip per day
                        // .datastoreLocation(.applicationDefault)
                        // .cloudKitContainer(.named("iCloud.com.app"))  // Sync across devices
                    ])
                }
        }
    }
}
```

Display frequency options: `.immediate` (no limit), `.hourly`, `.daily`, `.weekly`, `.monthly`.

## Defining a Tip

```swift
struct FavoriteTip: Tip {
    var title: Text { Text("Save as Favorite") }

    var message: Text? { Text("Favorites appear at the top of the list.") }

    var image: Image? { Image(systemName: "star") }

    // Optional: custom tip options
    var options: [any TipOption] {
        Tips.MaxDisplayCount(3)  // Show max 3 times
    }
}
```

## Displaying Tips

### Inline TipView

```swift
struct FeatureView: View {
    let favoriteTip = FavoriteTip()

    var body: some View {
        VStack {
            TipView(favoriteTip)  // Inline banner
            // Feature content below
        }
    }
}
```

### Popover Tip

```swift
Button("Favorite") { toggleFavorite() }
    .popoverTip(FavoriteTip(), arrowEdge: .bottom)
```

### TipView with Action

```swift
TipView(favoriteTip) { action in
    if action.id == "learn-more" {
        showLearnMore()
    }
}
```

### Tip Actions

```swift
struct FavoriteTip: Tip {
    var title: Text { Text("Save as Favorite") }
    var message: Text? { Text("Tap the star to save.") }
    var actions: [Action] {
        Action(id: "learn-more", title: "Learn More")
    }
}
```

## Eligibility Rules

### Parameter-Based Rules (State Conditions)

```swift
struct FavoriteTip: Tip {
    @Parameter
    static var isLoggedIn: Bool = false

    var rules: [Rule] {
        #Rule(Self.$isLoggedIn) { $0 }  // Show only when logged in
    }
}

// Update the parameter
FavoriteTip.isLoggedIn = true
```

### Event-Based Rules (Usage Patterns)

```swift
struct FavoriteTip: Tip {
    static let viewedDetail = Tips.Event(id: "viewedDetail")

    var rules: [Rule] {
        #Rule(Self.viewedDetail) { $0.donations.count >= 3 }  // After viewing 3 details
    }
}

// Donate to the event when the action occurs
FavoriteTip.viewedDetail.sendDonation()
```

### Combined Rules

```swift
var rules: [Rule] {
    #Rule(Self.$isLoggedIn) { $0 }
    #Rule(Self.viewedDetail) { $0.donations.count >= 3 }
}
// ALL rules must be satisfied (AND logic)
```

## Invalidation

```swift
let tip = FavoriteTip()

// When user performs the action
tip.invalidate(reason: .actionPerformed)

// Other reasons
tip.invalidate(reason: .displayCountExceeded)
tip.invalidate(reason: .tipClosed)
```

## Tip Status

```swift
switch tip.status {
case .available:    // Ready to show
case .invalidated(let reason): // Already dismissed/completed
case .pending:      // Rules not yet met
}
```

## Testing

```swift
// Show all tips regardless of rules
try? Tips.configure([.displayFrequency(.immediate)])
Tips.showAllTipsForTesting()

// Hide all tips
Tips.hideAllTipsForTesting()

// Show specific tip
Tips.showTipsForTesting([FavoriteTip.self])

// Reset all tip data (debug only)
try? Tips.resetDatastore()
```
