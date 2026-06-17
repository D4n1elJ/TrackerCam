---
name: ios-frameworks-core-location
description: Use when implementing or debugging Core Location authorization, CLServiceSession, CLMonitor, background location, or async location updates.
---

# Core Location

Review and write Core Location code for correct authorization, battery efficiency, and background reliability.

## Responsibility

**Owns:** Authorization strategy (When In Use vs Always), CLServiceSession layering, CLLocationUpdate async sequences, CLMonitor geofencing, CLBackgroundActivitySession, accuracy selection, permission denial recovery, geocoding.

**Does NOT own:** MapKit rendering (see swiftui-patterns), server-side geospatial queries, motion/activity recognition (Core Motion).

## Core Principles

1. **Start with When In Use.** Always authorization has 30-60% denial rates when requested upfront. Start minimal, upgrade when the user triggers a background feature.
2. **Declare goals, don't manage state machines.** Use CLServiceSession (iOS 18+) to tell Core Location what you need. Layer sessions rather than replacing them.
3. **CLMonitor for geofencing, not continuous updates.** Polling location to check proximity drains 10x more battery than system-managed CLMonitor conditions.
4. **Handle denial gracefully.** Check `authorizationDenied` and `authorizationDeniedGlobally` on every update. Offer manual alternatives.
5. **Cancel when done.** Store location Tasks in properties and cancel them when the feature is inactive. Dangling iterations keep the location icon lit and drain battery.
6. **Match accuracy to need.** `.automotiveNavigation` for turn-by-turn, `.default` for weather. Higher accuracy = higher battery drain.
7. **Hold background sessions as properties.** `CLBackgroundActivitySession` stored in a local variable deallocates immediately and silently stops background access.

## Authorization Decision Tree

```
Does this feature REQUIRE background location?
├── NO --> CLServiceSession(authorization: .whenInUse)
│   └── Needs precise location?
│       ├── ALWAYS --> add fullAccuracyPurposeKey
│       └── SOMETIMES --> layer a full-accuracy session when feature active
│
└── YES --> start with .whenInUse, upgrade to .always on user action
    └── When does user first need background?
        ├── IMMEDIATELY (fitness tracker) --> request .always on first tracking start
        └── LATER (geofence reminders) --> request .always when user creates first geofence
```

## Monitoring Strategy

```
What are you monitoring?
├── USER POSITION (continuous) --> CLLocationUpdate.liveUpdates()
│   ├── Driving nav --> .automotiveNavigation
│   ├── Walking/cycling --> .otherNavigation
│   ├── Fitness --> .fitness
│   └── General --> .default
│
├── REGION ENTRY/EXIT --> CLMonitor + CircularGeographicCondition
│   └── Max 20 conditions per app — swap dynamically by proximity
│
└── SIGNIFICANT CHANGES ONLY --> startMonitoringSignificantLocationChanges() (legacy)
```

## Red Flags

| Anti-Pattern | Problem | Time Cost |
|---|---|---|
| Premature Always authorization | 30-60% denial rate, feature adoption destroyed | 15 min fix, permanent user loss |
| Continuous updates for geofencing | 10x battery drain vs CLMonitor | 5 min refactor |
| Ignoring `isStationary` | Wasted battery when device not moving | 2 min to add check |
| No denial handling | Silent failure, confused users | 10 min to add fallback |
| Wrong accuracy for use case | Battery drain for city-level features using nav accuracy | 1 min to change config |
| Not cancelling location Tasks | Location icon persists, battery drain continues | 5 min to add cancellation |
| CLBackgroundActivitySession in local variable | Deallocates immediately, background silently stops | 2 min to move to property |
| Manual auth state machine (iOS 18+) | Fragile, hard to maintain, bugs on edge cases | 30 min to migrate to CLServiceSession |

## CLServiceSession Layering (iOS 18+)

Don't replace sessions -- layer them. Each session declares a goal; Core Location merges all active goals.

```swift
// Base session for the app
let baseSession = CLServiceSession(authorization: .whenInUse)

// Additional session when navigation feature is active
var navSession: CLServiceSession?

func startNavigation() {
    navSession = CLServiceSession(
        authorization: .whenInUse,
        fullAccuracyPurposeKey: "Navigation"
    )
}

func stopNavigation() {
    navSession = nil  // goal removed, base session remains
}
```

Iterating `CLLocationUpdate.liveUpdates()` or `CLMonitor.events` creates an implicit `.whenInUse` session. Disable with:

```xml
<key>NSLocationRequireExplicitServiceSession</key>
<true/>
```

## Pre-Ship Checklist

- [ ] `NSLocationWhenInUseUsageDescription` in Info.plist with clear user benefit
- [ ] `NSLocationAlwaysAndWhenInUseUsageDescription` if using Always (explains background value)
- [ ] Authorization starts at `.whenInUse`, upgrades only on user action
- [ ] Denial handled with manual alternative (picker, search, manual entry)
- [ ] Location Tasks cancelled when feature inactive
- [ ] `isStationary` checked to avoid wasted processing
- [ ] Accuracy config matches use case (not `.automotiveNavigation` for weather)
- [ ] Background: `CLBackgroundActivitySession` held as property, started from foreground
- [ ] Background: session recreated in `didFinishLaunchingWithOptions` on relaunch
- [ ] Geofencing: condition count stays under 20, radii >= 100m
- [ ] Tested authorization denial, reduced accuracy, and background transitions on device

## References

- `references/authorization-patterns.md` -- Progressive authorization, CLServiceSession, CLBackgroundActivitySession, permission denial recovery
- `references/monitoring-and-updates.md` -- CLLocationUpdate, CLMonitor, geofence limits, beacons, visit monitoring, background updates, GeoJSON coordinate order, GeoToolbox
- `references/diagnostics.md` -- Symptom-based troubleshooting: no updates, background broken, auth denied, poor accuracy, geofence silent, icon stuck, console debugging
