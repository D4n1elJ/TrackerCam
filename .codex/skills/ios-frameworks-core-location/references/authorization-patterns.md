# Authorization Patterns

## Progressive Authorization Strategy

Never request the maximum authorization level upfront. Users deny aggressive requests and cannot easily reverse that decision.

### Phase 1: When In Use (default)

```swift
import CoreLocation

// Declare intent -- Core Location prompts the user
let session = CLServiceSession(authorization: .whenInUse)

// Start receiving updates (also creates implicit .whenInUse session)
for try await update in CLLocationUpdate.liveUpdates() {
    guard let location = update.location else { continue }
    showNearbyResults(for: location)
}
```

### Phase 2: Full Accuracy (on demand)

Layer a full-accuracy session when a precision feature activates. Requires `NSLocationTemporaryUsageDescriptionDictionary` in Info.plist.

```swift
var navSession: CLServiceSession?

func startNavigation() {
    // Layer on top of existing .whenInUse session
    navSession = CLServiceSession(
        authorization: .whenInUse,
        fullAccuracyPurposeKey: "Navigation"
    )
}

func stopNavigation() {
    navSession = nil  // full-accuracy goal removed
}
```

### Phase 3: Always (only when user triggers background feature)

```swift
var alwaysSession: CLServiceSession?

func userCreatedGeofenceReminder() {
    // User just created a location-based reminder -- NOW request Always
    alwaysSession = CLServiceSession(authorization: .always)
}
```

The upgrade prompt only appears when the user understands why background access matters. Denial rate drops from 30-60% to 5-10%.

## CLServiceSession (iOS 18+)

Declarative authorization. Tell Core Location what you need; it handles prompts, state transitions, and edge cases.

### Session Types

```swift
CLServiceSession(authorization: .none)       // No authorization request
CLServiceSession(authorization: .whenInUse)  // Request When In Use
CLServiceSession(authorization: .always)     // Request Always (must start from foreground)
```

### Session Layering

Multiple sessions coexist. Core Location merges all active goals. Don't replace sessions -- create new ones for additional requirements.

```swift
// App-level baseline
let baseSession = CLServiceSession(authorization: .whenInUse)

// Feature-level addition
let preciseSession = CLServiceSession(
    authorization: .whenInUse,
    fullAccuracyPurposeKey: "Directions"
)
// Both active simultaneously. When preciseSession is released, base remains.
```

### Monitoring Diagnostics

```swift
for try await diagnostic in session.diagnostics {
    if diagnostic.authorizationDenied {
        showDeniedUI()
        break
    }
    if diagnostic.authorizationDeniedGlobally {
        showLocationServicesDisabledUI()
        break
    }
    if diagnostic.insufficientlyInUse {
        // App not in foreground -- can't request authorization now
        break
    }
    if diagnostic.alwaysAuthorizationDenied {
        // Always specifically denied, When In Use may still work
        fallBackToWhenInUse()
        break
    }
    if !diagnostic.authorizationRequestInProgress {
        // User made a decision
        break
    }
}
```

### Session Lifecycle

Sessions survive backgrounding, suspension, and termination. On relaunch, recreate sessions immediately in `didFinishLaunchingWithOptions` -- Core Location tracks that the app had active sessions.

## CLBackgroundActivitySession

Enables background location with When In Use authorization. Shows the blue status bar indicator.

### Critical Rules

1. **Hold as a property.** A local variable deallocates at end of scope, silently killing background access.
2. **Start from foreground.** Cannot create a new session while backgrounded.
3. **Recreate on relaunch.** If app is terminated while tracking, recreate the session on next launch.

```swift
class LocationTracker {
    // PROPERTY -- not a local variable
    private var backgroundSession: CLBackgroundActivitySession?
    private var locationTask: Task<Void, Error>?

    func startBackgroundTracking() {
        // Must call from foreground
        backgroundSession = CLBackgroundActivitySession()

        locationTask = Task {
            for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                if Task.isCancelled { break }
                if let location = update.location {
                    recordTrack(location)
                }
            }
        }
    }

    func stopBackgroundTracking() {
        locationTask?.cancel()
        locationTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
    }
}
```

### Relaunch Recovery

```swift
// In AppDelegate or @main App init
func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    if UserDefaults.standard.bool(forKey: "wasTrackingLocation") {
        backgroundSession = CLBackgroundActivitySession()
        startLocationUpdates()
    }
    return true
}
```

### Requirements

- Signing & Capabilities: Background Modes with "Location updates" checked
- Info.plist: `UIBackgroundModes` array containing `location`
- Authorization: `.authorizedWhenInUse` is sufficient (blue indicator shown)

## When In Use vs Always Decision Framework

| Factor | When In Use | Always |
|---|---|---|
| User sees location icon | Blue indicator when backgrounded | Arrow in status bar |
| Approval rate (upfront) | 70-80% | 40-50% |
| Approval rate (contextual) | 85-95% | 70-80% |
| Background access | Yes, with CLBackgroundActivitySession | Yes, without indicator |
| Geofence wakeups | Yes, with CLMonitor | Yes, with CLMonitor |
| Use when | App tracks during active sessions (runs, drives) | App must wake silently (arrival alerts, background sync) |

**Default to When In Use.** Only request Always when the feature genuinely requires silent background wakeups without a visible tracking session.

## Permission Denial Recovery

### Detecting Denial

```swift
// Modern (iOS 17+ via CLLocationUpdate)
for try await update in CLLocationUpdate.liveUpdates() {
    if update.authorizationDenied {
        showLocationDeniedRecovery()
        break
    }
    if update.authorizationDeniedGlobally {
        showSystemLocationDisabledMessage()
        break
    }
    if update.accuracyLimited {
        // Reduced accuracy -- updates every 15-20 min, ~5km radius
        handleReducedAccuracy()
    }
    if let location = update.location {
        processLocation(location)
    }
}
```

### Recovery UI Pattern

```swift
struct LocationDeniedView: View {
    var body: some View {
        ContentUnavailableView(
            "Location Access Required",
            systemImage: "location.slash",
            description: Text("Enable location access to see nearby places.")
        )
        .overlay(alignment: .bottom) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 40)
        }
    }
}
```

### Graceful Degradation Strategies

| Denied Feature | Fallback |
|---|---|
| Nearby search | Manual city/zip entry, search by name |
| Map centering | Default to last known location or country center |
| Distance display | Hide distance, show address only |
| Geofence reminders | Time-based reminders instead |
| Weather by location | Manual city selection |

### Info.plist Usage Strings

Compelling strings reduce denial rates. State the specific user benefit, not the technical requirement.

```xml
<!-- Weak: tells user nothing -->
<string>This app needs your location.</string>

<!-- Strong: states specific benefit -->
<string>Your location shows restaurants, shops, and attractions within walking distance.</string>

<!-- Always: explains background value -->
<string>Background location sends you a reminder when you arrive at saved places, even when the app is closed.</string>
```
