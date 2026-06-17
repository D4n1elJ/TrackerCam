# Diagnostics

Symptom-based troubleshooting for Core Location issues.

## Symptom 1: Location Updates Never Arrive

### Quick Checks

```swift
let manager = CLLocationManager()
print("Authorization: \(manager.authorizationStatus.rawValue)")
// 0=notDetermined, 1=restricted, 2=denied, 3=authorizedAlways, 4=authorizedWhenInUse
print("Services enabled: \(CLLocationManager.locationServicesEnabled())")
print("Accuracy: \(manager.accuracyAuthorization == .fullAccuracy ? "full" : "reduced")")
```

### Decision Tree

```
Q1: authorizationStatus?
├── .notDetermined --> never requested
│   Fix: CLServiceSession(authorization: .whenInUse) or iterate liveUpdates()
├── .denied --> user refused
│   Fix: show recovery UI, link to Settings
├── .restricted --> parental controls / MDM
│   Fix: offer manual location input
└── .authorizedWhenInUse / .authorizedAlways --> check next

Q2: locationServicesEnabled()?
├── NO --> disabled system-wide
│   Fix: prompt user to enable in Settings > Privacy > Location Services
└── YES --> check next

Q3: Are you iterating the AsyncSequence?
├── NO --> updates only arrive when you await
│   Fix: Task { for try await update in CLLocationUpdate.liveUpdates() { ... } }
└── YES --> check next

Q4: Is the Task alive?
├── Cancelled or local variable --> died before updates arrived
│   Fix: store Task in a property, not a local variable
└── Alive --> check next

Q5: Check update properties
├── update.locationUnavailable --> no GPS fix (indoors, airplane mode)
│   Fix: wait or inform user
├── update.authorizationDenied --> handle denial
└── update.insufficientlyInUse --> app not in foreground, can't prompt
```

### Info.plist Checklist

Missing these keys = silent failure with no prompt:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Clear user benefit here</string>

<!-- Only if using Always -->
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Why background access matters to the user</string>
```

---

## Symptom 2: Background Location Not Working

### Decision Tree

```
Q1: "Location updates" checked in Background Modes capability?
├── NO --> silently disabled
│   Fix: Xcode > Signing & Capabilities > Background Modes > Location updates
└── YES --> check next

Q2: Holding CLBackgroundActivitySession as a property?
├── NO / local variable --> deallocates, background silently stops
│   Fix: var backgroundSession: CLBackgroundActivitySession?
└── YES --> check next

Q3: Session started from foreground?
├── NO --> cannot create new session while backgrounded
│   Fix: create CLBackgroundActivitySession while app is in foreground
└── YES --> check next

Q4: Recreating session on relaunch?
├── NO --> app terminated, session lost
│   Fix: in didFinishLaunchingWithOptions, check persisted flag and recreate
└── YES --> check authorization

Q5: Authorization level?
├── .authorizedWhenInUse --> fine with CLBackgroundActivitySession (blue indicator)
├── .authorizedAlways --> should work, check session lifecycle
└── .denied --> no background access possible
```

### Common Mistake

```swift
// WRONG: local variable deallocates immediately
func startTracking() {
    let session = CLBackgroundActivitySession()  // dies at end of function
    startLocationUpdates()
}

// RIGHT: property keeps session alive
var backgroundSession: CLBackgroundActivitySession?

func startTracking() {
    backgroundSession = CLBackgroundActivitySession()
    startLocationUpdates()
}
```

---

## Symptom 3: Authorization Always Denied

### Decision Tree

```
Q1: Fresh install with immediate denial?
├── YES --> missing or empty NSLocationWhenInUseUsageDescription = automatic denial
└── NO --> check next

Q2: User previously denied?
├── YES --> must re-enable in Settings manually
│   Fix: show recovery UI with Settings link:
│        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
└── NO --> check next

Q3: Requesting at wrong time?
├── insufficientlyInUse --> app not in foreground
│   Fix: only request authorization during foreground user interaction
└── NO --> check next

Q4: Device restricted?
├── .restricted --> parental controls / MDM, cannot override
│   Fix: offer manual location input
└── NO --> review Info.plist strings

Q5: Are Info.plist strings compelling?
├── Bad: "This app needs your location."
└── Good: "Your location shows restaurants within walking distance."
```

---

## Symptom 4: Location Accuracy Unexpectedly Poor

### Decision Tree

```
Q1: accuracyAuthorization?
├── .reducedAccuracy --> user chose approximate location
│   Options: accept it, request temporary full accuracy via CLServiceSession
│   with fullAccuracyPurposeKey, or explain value and link to Settings
└── .fullAccuracy --> check environment

Q2: horizontalAccuracy value?
├── < 0 --> INVALID location, do not use
│   Fix: guard location.horizontalAccuracy >= 0 else { continue }
├── > 100m --> WiFi/cell only (indoors, no GPS)
│   Fix: user needs better location or wait for GPS lock
├── 10-100m --> normal for most use cases
│   If need better: use .automotiveNavigation or .otherNavigation
└── < 10m --> good GPS accuracy

Q3: LiveConfiguration?
├── .default or omitted --> system manages, may prioritize battery
│   If need more: use .fitness, .otherNavigation, .automotiveNavigation
└── .automotiveNavigation --> highest accuracy, highest battery

Q4: Stale location?
├── Check location.timestamp -- if old, device hasn't moved or updates paused
└── Recent but poor accuracy --> environmental issue (urban canyon, indoors)
```

---

## Symptom 5: Geofence Events Not Triggering

### Quick Checks

```swift
let monitor = await CLMonitor("MyMonitor")
let count = await monitor.identifiers.count
print("Conditions: \(count)/20")

if let record = await monitor.record(for: "MyGeofence") {
    print("State: \(record.lastEvent.state)")
    print("Date: \(record.lastEvent.date)")
    if let geo = record.condition as? CLMonitor.CircularGeographicCondition {
        print("Radius: \(geo.radius)m")
    }
}
```

### Decision Tree

```
Q1: Condition count?
├── 20 --> at limit, new conditions silently ignored
│   Fix: prioritize, swap dynamically by proximity
│   Check: lastEvent.conditionLimitExceeded
└── < 20 --> check next

Q2: Radius?
├── < 100m --> unreliable, may never trigger
│   Fix: use minimum 100m radius
└── >= 100m --> check next

Q3: Awaiting monitor.events?
├── NO --> events not processed, lastEvent never updates
│   Fix: Task { for try await event in monitor.events { ... } }
└── YES --> check next

Q4: Monitor reinitialized on app launch?
├── NO --> conditions persist but monitor instance must be recreated
│   Fix: recreate CLMonitor with same name in didFinishLaunchingWithOptions
└── YES --> check next

Q5: lastEvent state?
├── .unknown --> system hasn't determined state yet
├── .satisfied --> inside region, waiting for exit
├── .unsatisfied --> outside region, waiting for entry
└── Check lastEvent.date -- if very old, may not be monitoring correctly

Q6: accuracyLimited?
├── YES --> reduced accuracy prevents reliable geofencing
│   Fix: request full accuracy
└── NO --> check environment (device must have location access)
```

### Common Mistakes

```swift
// WRONG: not awaiting events
let monitor = await CLMonitor("Test")
await monitor.add(condition, identifier: "Place")
// Nothing happens -- no Task awaiting events

// WRONG: multiple monitors with same name = undefined behavior
let monitor1 = await CLMonitor("App")
let monitor2 = await CLMonitor("App")  // DO NOT DO THIS

// RIGHT: one instance per name, always await events
class LocationService {
    private var monitor: CLMonitor?

    func setup() async {
        monitor = await CLMonitor("App")
        Task { for try await event in monitor!.events { handleEvent(event) } }
    }
}
```

---

## Symptom 6: Location Icon Won't Go Away

### Decision Tree

```
Q1: Still iterating liveUpdates()?
├── YES --> cancel the Task or break from loop
│   Fix: locationTask?.cancel()
└── NO --> check next

Q2: CLBackgroundActivitySession still held?
├── YES --> keeping location access active
│   Fix: backgroundSession?.invalidate(); backgroundSession = nil
└── NO --> check next

Q3: CLMonitor still monitoring conditions?
├── YES --> expected behavior, icon shows monitoring active
│   Fix if done: remove all conditions
└── NO --> check next

Q4: Legacy CLLocationManager still running?
├── Check: stopUpdatingLocation(), stopMonitoring(for:) for all regions
└── NO --> check other frameworks (MapKit showsUserLocation, Core Motion)
```

### Force Stop All Location

```swift
// Modern APIs
locationTask?.cancel()
backgroundSession?.invalidate()
backgroundSession = nil
for id in await monitor.identifiers { await monitor.remove(id) }

// Legacy APIs
manager.stopUpdatingLocation()
manager.stopMonitoringSignificantLocationChanges()
manager.stopMonitoringVisits()
for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
```

---

## Console Debugging

```bash
# View locationd logs
log stream --predicate 'subsystem == "com.apple.locationd"' --level debug

# View app-specific Core Location logs
log stream --predicate 'subsystem == "com.apple.CoreLocation"' --level debug

# Filter for specific process
log stream --predicate 'process == "YourApp" AND subsystem == "com.apple.CoreLocation"'
```

### Common Log Messages

| Log Message | Meaning |
|---|---|
| `Client is not authorized` | Authorization denied or not requested |
| `Location services disabled` | System-wide toggle off |
| `Accuracy authorization is reduced` | User chose approximate location |
| `Condition limit exceeded` | At 20-condition maximum |
| `Background location access denied` | Missing background capability or session |
