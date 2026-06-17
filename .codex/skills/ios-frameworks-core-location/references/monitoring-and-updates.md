# Monitoring and Updates

## CLLocationUpdate Async Sequence (iOS 17+)

### Basic Usage

```swift
import CoreLocation

Task {
    for try await update in CLLocationUpdate.liveUpdates() {
        if update.authorizationDenied {
            showManualLocationPicker()
            break
        }
        if let location = update.location {
            processLocation(location)
        }
        if update.isStationary {
            saveLastKnownLocation(update.location)
            // Updates pause automatically, resume when device moves
        }
    }
}
```

### LiveConfiguration Selection

| Configuration | Accuracy | Battery | Use For |
|---|---|---|---|
| `.automotiveNavigation` | ~5m | Highest | Turn-by-turn driving directions |
| `.otherNavigation` | ~10m | High | Walking/cycling navigation |
| `.fitness` | ~10m | High | Run/ride tracking |
| `.airborne` | varies | High | Aviation apps |
| `.default` (or omit) | ~10-100m | Medium | Store finder, weather, general |

```swift
// Navigation
for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) { ... }

// Fitness tracking
for try await update in CLLocationUpdate.liveUpdates(.fitness) { ... }

// General (city-level is fine)
for try await update in CLLocationUpdate.liveUpdates() { ... }
```

### Key Properties

| Property | Type | Meaning |
|---|---|---|
| `location` | `CLLocation?` | Current position (nil if unavailable) |
| `isStationary` | `Bool` | Device stopped moving; updates pause automatically |
| `authorizationDenied` | `Bool` | User denied location access |
| `authorizationDeniedGlobally` | `Bool` | Location services disabled system-wide |
| `accuracyLimited` | `Bool` | Reduced accuracy (~5km, updates every 15-20 min) |
| `locationUnavailable` | `Bool` | Cannot determine position (indoors, airplane mode) |
| `insufficientlyInUse` | `Bool` | App not in foreground; cannot prompt for auth |

### Cancellation

Always store the Task and cancel when the feature is inactive. Dangling iterations keep the location icon lit.

```swift
private var locationTask: Task<Void, Error>?

func startTracking() {
    locationTask = Task {
        for try await update in CLLocationUpdate.liveUpdates(.fitness) {
            if Task.isCancelled { break }
            processUpdate(update)
        }
    }
}

func stopTracking() {
    locationTask?.cancel()
    locationTask = nil
}
```

In SwiftUI, `.task` handles cancellation automatically:

```swift
struct NearbyView: View {
    @State private var location: CLLocation?

    var body: some View {
        content
            .task {
                for try await update in CLLocationUpdate.liveUpdates() {
                    location = update.location
                }
            }
    }
}
```

## CLMonitor for Geofencing (iOS 17+)

CLMonitor is a Swift actor that replaces legacy `CLCircularRegion` monitoring.

### Basic Geofencing

```swift
let monitor = await CLMonitor("PlaceReminders")

// Add a geofence
let condition = CLMonitor.CircularGeographicCondition(
    center: CLLocationCoordinate2D(latitude: 37.33, longitude: -122.01),
    radius: 200  // meters, minimum ~100m for reliability
)
await monitor.add(condition, identifier: "office")

// Listen for events
for try await event in monitor.events {
    switch event.state {
    case .satisfied:   handleArrival(event.identifier)
    case .unsatisfied: handleDeparture(event.identifier)
    case .unknown:     break
    @unknown default:  break
    }
}
```

### Condition Management

```swift
// Add with assumed initial state
await monitor.add(condition, identifier: "home", assuming: .unsatisfied)

// Remove a condition
await monitor.remove("office")

// List all monitored identifiers
let ids = await monitor.identifiers

// Check a specific record
if let record = await monitor.record(for: "office") {
    let state = record.lastEvent.state
    let when = record.lastEvent.date
}
```

### Critical Rules

1. **One instance per name.** Creating two `CLMonitor("Same")` instances is undefined behavior.
2. **Always await events.** Events only become `lastEvent` after your code handles them from the `events` sequence.
3. **Reinitialize on launch.** Conditions persist, but the monitor instance must be recreated in `didFinishLaunchingWithOptions`.

## Geofence 20-Condition Limit

Each app can monitor a maximum of 20 conditions simultaneously. Exceeding the limit silently drops new conditions (check `event.conditionLimitExceeded`).

### Dynamic Swap Strategy

Track the user's rough position and rotate the 20 slots to cover the nearest points of interest.

```swift
func updateMonitoredRegions(near userLocation: CLLocation) async {
    let nearest = allPOIs
        .sorted { $0.coordinate.distance(to: userLocation) < $1.coordinate.distance(to: userLocation) }
        .prefix(20)

    let desiredIDs = Set(nearest.map(\.id))
    let currentIDs = Set(await monitor.identifiers)

    // Remove stale
    for id in currentIDs.subtracting(desiredIDs) {
        await monitor.remove(id)
    }

    // Add new
    for poi in nearest where !currentIDs.contains(poi.id) {
        let condition = CLMonitor.CircularGeographicCondition(
            center: poi.coordinate,
            radius: max(poi.radius, 100)  // enforce minimum
        )
        await monitor.add(condition, identifier: poi.id)
    }
}
```

Trigger the swap on significant location changes or when the user scrolls the map to a new area.

### Radius Guidelines

| Radius | Reliability | Use For |
|---|---|---|
| < 100m | Unreliable, may never trigger | Avoid |
| 100-200m | Reliable, slight delay on entry/exit | Store arrival, parking |
| 200-500m | Very reliable | City landmarks, neighborhoods |
| 500m+ | Highly reliable, wide trigger zone | Metro areas |

Exit events can lag 3-5 minutes after the user leaves the radius.

## Background Location Updates

### With CLBackgroundActivitySession (When In Use)

```swift
class BackgroundTracker {
    private var backgroundSession: CLBackgroundActivitySession?
    private var locationTask: Task<Void, Error>?

    func start() {
        backgroundSession = CLBackgroundActivitySession()  // must hold as property
        locationTask = Task {
            for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                if Task.isCancelled { break }
                guard let location = update.location else { continue }
                record(location)
            }
        }
    }

    func stop() {
        locationTask?.cancel()
        locationTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
    }
}
```

Blue indicator appears when app is backgrounded. Requires Background Modes capability with "Location updates".

### Relaunch Recovery

Core Location can terminate and relaunch the app. Persist tracking state and recreate sessions on launch.

```swift
func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    if UserDefaults.standard.bool(forKey: "isTrackingLocation") {
        backgroundSession = CLBackgroundActivitySession()
        startLocationUpdates()
    }

    // Reinitialize CLMonitor with the same name to resume geofence events
    Task {
        monitor = await CLMonitor("PlaceReminders")
        Task { for try await event in monitor.events { handleEvent(event) } }
    }

    return true
}
```

## GeoJSON Coordinate Order Trap

GeoJSON uses **longitude, latitude** order. CLLocationCoordinate2D uses **latitude, longitude**. Mixing them places points on the wrong continent.

```swift
// GeoJSON: [longitude, latitude]
let geoJSON = [-122.01, 37.33]

// CoreLocation: latitude first
let coordinate = CLLocationCoordinate2D(
    latitude: geoJSON[1],   // 37.33
    longitude: geoJSON[0]   // -122.01
)

// WRONG -- swapped, lands in Antarctica or the ocean
let wrong = CLLocationCoordinate2D(
    latitude: geoJSON[0],   // -122.01
    longitude: geoJSON[1]   // 37.33
)
```

Quick sanity check: latitude is -90 to 90, longitude is -180 to 180. If latitude is outside +/-90, you swapped them.

## GeoToolbox and PlaceDescriptor (iOS 26+)

iOS 26 introduces the GeoToolbox framework with `PlaceDescriptor` for structured place information.

```swift
import GeoToolbox

// Describe a place from coordinates
let descriptor = try await PlaceDescriptor(
    location: CLLocation(latitude: 37.33, longitude: -122.01)
)

let name = descriptor.name                  // "Apple Park"
let locality = descriptor.locality          // "Cupertino"
let administrativeArea = descriptor.administrativeArea  // "CA"
```

`PlaceDescriptor` replaces many `CLGeocoder.reverseGeocodeLocation` use cases with a more structured API. Use it for new code targeting iOS 26+; fall back to `CLGeocoder` for earlier versions.

## Geocoding (CLGeocoder)

### Forward Geocoding (address to coordinate)

```swift
let geocoder = CLGeocoder()

func geocode(_ address: String) async throws -> CLLocation? {
    let placemarks = try await geocoder.geocodeAddressString(address)
    return placemarks.first?.location
}
```

### Reverse Geocoding (coordinate to address)

```swift
func reverseGeocode(_ location: CLLocation) async throws -> CLPlacemark? {
    let placemarks = try await geocoder.reverseGeocodeLocation(location)
    return placemarks.first
}
```

### Rate Limits

- One request at a time -- `CLGeocoder` throws if a request is already in progress
- Apple throttles aggressively -- cache results, don't re-geocode the same input
- Cancel before starting a new request: `geocoder.cancelGeocode()`

## Beacon Monitoring (CLMonitor)

CLMonitor supports beacon proximity detection alongside geographic conditions.

### BeaconIdentityCondition

Three granularity levels, from broadest to most specific:

```swift
// All beacons with this UUID (any site)
let anyBeacon = CLMonitor.BeaconIdentityCondition(uuid: myUUID)

// Specific site (UUID + major)
let siteBeacon = CLMonitor.BeaconIdentityCondition(uuid: myUUID, major: 100)

// Specific beacon (UUID + major + minor)
let exactBeacon = CLMonitor.BeaconIdentityCondition(uuid: myUUID, major: 100, minor: 5)
```

Add and monitor like geographic conditions:

```swift
await monitor.add(siteBeacon, identifier: "lobby-entrance")

for try await event in monitor.events {
    if event.state == .satisfied {
        // Beacon detected -- event.refinement contains actual UUID/major/minor
        handleBeaconDetected(event)
    }
}
```

Beacons share the same 20-condition limit with geographic conditions.

## Visit Monitoring (Legacy)

Detect arrivals and departures from places the user spends time. Low-power, system-managed.

```swift
manager.startMonitoringVisits()

func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    let arrival = visit.arrivalDate     // .distantPast if arrival unknown
    let departure = visit.departureDate // .distantFuture if still there
    let coordinate = visit.coordinate
    let accuracy = visit.horizontalAccuracy
}
```

Visits are coarse-grained (system decides what counts as a "visit") and arrive with significant delay. Use for analytics and journaling, not real-time features. Works in background without CLBackgroundActivitySession.

## Diagnostics Quick Reference

See `references/diagnostics.md` for full symptom-based decision trees.

| Symptom | Check |
|---|---|
| No location updates | Authorization status, Info.plist keys, Task alive |
| Background stops | CLBackgroundActivitySession held as property, started from foreground |
| Always auth not working | CLServiceSession with `.always`, started in foreground |
| Geofence not triggering | Condition count (max 20), radius (min 100m), awaiting `monitor.events` |
| Reduced accuracy only | `accuracyAuthorization`, request temporary full accuracy via CLServiceSession |
| Location icon persists | Cancel location Task, invalidate background session, remove CLMonitor conditions |
| Coordinates on wrong continent | GeoJSON lng/lat vs CoreLocation lat/lng swap |

### Console Debugging

```bash
# View locationd logs
log stream --predicate 'subsystem == "com.apple.locationd"' --level debug

# View app-specific Core Location logs
log stream --predicate 'subsystem == "com.apple.CoreLocation"' --level debug

# Filter for specific process
log stream --predicate 'process == "YourApp" AND subsystem == "com.apple.CoreLocation"'
```
