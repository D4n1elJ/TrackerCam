# iOS Energy

## Responsibility

**Owns:** Energy diagnosis workflow, Power Profiler interpretation, subsystem identification (CPU/GPU/Network/Location/Display), energy anti-patterns and fixes, timer efficiency, polling elimination, Low Power Mode adaptation, thermal state handling, MetricKit energy monitoring, energy audit checklists.

**Does NOT own:** Location API details (see `core-location`), background task scheduling mechanics (see `background-tasks`), networking API patterns (see `ios-networking`), hang diagnosis (see `hang-diagnostics`), general performance profiling with Time Profiler (see `ios-tooling`), GPU render pipeline optimization (see `metal`).

## Core Principles

1. **Measure before optimizing.** Use Power Profiler to identify the dominant subsystem. Guessing wastes hours; profiling takes 15 minutes.
2. **Energy is a cross-cutting concern.** Battery drain comes from CPU, GPU, Network, Display, or Location. The fix depends on which.
3. **Eliminate work, don't just optimize it.** Event-driven beats polling. Lazy beats eager. Caching beats re-parsing.
4. **Respect system signals.** Respond to Low Power Mode and thermal state. Use discretionary scheduling.

## Diagnosis Workflow

### Step 1: Record a Power Trace

```
1. Connect iPhone wirelessly (cable charging zeroes power metrics)
2. Xcode > Product > Profile (Cmd+I)
3. Select Blank template > "+" > Add "Power Profiler"
4. Optional: Add "CPU Profiler" for correlation
5. Record 2-3 minutes of normal app usage
6. Stop and examine per-app metrics
```

### Step 2: Identify Dominant Subsystem

| Power Profiler Lane | High Value Indicates |
|---|---|
| CPU Power Impact | Timers, polling, parsing, eager loading |
| GPU Power Impact | Animations, blur, Metal rendering, high frame rate |
| Network Power Impact | Frequent requests, polling, large downloads |
| Display Power Impact | Light backgrounds on OLED, high brightness content |

Location drain appears in CPU lane. Confirm by checking if location icon is active.

### Step 3: Decision Tree

```
Battery drain reported
|
+-- CPU dominant?
|   +-- Continuous? --> Timer Efficiency / Push vs Poll / Lazy Loading
|   +-- Spikes on action? --> Cache parsed results, move to background
|   +-- High background? --> Location Efficiency / Background Execution
|
+-- Network dominant?
|   +-- Many small requests? --> Batch into fewer large requests
|   +-- Polling? --> Convert to push notifications
|   +-- Foreground downloads? --> Use discretionary background URLSession
|
+-- GPU dominant?
|   +-- Continuous animations? --> Stop when view not visible
|   +-- Blur effects? --> Reduce or remove
|   +-- High frame rate? --> Audit secondary frame rates
|
+-- Display dominant?
|   +-- Light backgrounds on OLED? --> Dark Mode (up to 70% savings)
|   +-- Screen always on? --> Allow sleep
|
+-- Location drain? (CPU + location icon)
    +-- Continuous updates? --> Significant-change monitoring
    +-- kCLLocationAccuracyBest? --> Reduce to HundredMeters
    +-- Background location? --> Evaluate necessity
```

## Energy Patterns

### Timer Efficiency

```swift
// BAD: No tolerance, prevents system batching
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    self.updateUI()
}

// GOOD: 10% tolerance allows batching
let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    self.updateUI()
}
timer.tolerance = 0.1

// BEST: Event-driven, no timer at all
NotificationCenter.default.publisher(for: .dataDidUpdate)
    .sink { [weak self] _ in self?.updateUI() }
    .store(in: &cancellables)
```

Rules:
- Set tolerance to at least 10% of interval
- Invalidate timers when no longer needed
- Stop timers when app enters background
- Prefer event-driven over polling

### Push vs Poll

Polling keeps radios active. Push activates radio only when data changes. Push is ~100x more energy-efficient than 5-second polling.

```swift
// BAD: Polls every 5 seconds
Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
    self?.fetchLatestData()
}

// GOOD: Background push notification triggers fetch only when data changes
// Server sends content-available: 1 with apns-priority: 5 (energy efficient)
```

### Lazy Loading

```swift
// BAD: VStack creates ALL views upfront (WWDC25-226: CPU impact 21)
VStack {
    ForEach(videos) { video in VideoCardView(video: video) }
}

// GOOD: LazyVStack creates on demand (WWDC25-226: CPU impact 4.3)
LazyVStack {
    ForEach(videos) { video in VideoCardView(video: video) }
}
```

### Cache Expensive Work

```swift
// BAD: Parses JSON on every location update
func suggestionsForLocation(_ location: CLLocation) -> [Video] {
    let data = try? Data(contentsOf: rulesFileURL)
    let rules = try? JSONDecoder().decode([Rule].self, from: data)
    return filter(using: rules)
}

// GOOD: Parse once
private lazy var cachedRules: [Rule] = {
    let data = try? Data(contentsOf: rulesFileURL)
    return (try? JSONDecoder().decode([Rule].self, from: data)) ?? []
}()

func suggestionsForLocation(_ location: CLLocation) -> [Video] {
    return filter(using: cachedRules)
}
```

### Location Accuracy

| Accuracy | Battery Impact | Use Case |
|---|---|---|
| `kCLLocationAccuracyBest` | Very High | Navigation only |
| `kCLLocationAccuracyNearestTenMeters` | High | Fitness tracking |
| `kCLLocationAccuracyHundredMeters` | Medium | Store locators, weather |
| `kCLLocationAccuracyKilometer` | Low | Regional content |
| Significant-change monitoring | Very Low | Background updates |

For details on CLLocationUpdate async patterns and stationary detection, see `ios-core-location`.

### Frame Rate Alignment

```swift
// BAD: Secondary animation runs at full 60fps unnecessarily

// GOOD: Match secondary content frame rate
let displayLink = CADisplayLink(target: self, selector: #selector(update))
displayLink.preferredFrameRateRange = CAFrameRateRange(
    minimum: 10, maximum: 30, preferred: 30
)
displayLink.add(to: .current, forMode: .default)
```

Aligning secondary animation frame rates saves up to 20% GPU power (WWDC22-10083).

### Audio Session Cleanup

```swift
// BAD: Audio session stays active after playback stops, hardware stays powered
func stopPlayback() {
    player.stop()
}

// GOOD: Deactivate when done
func stopPlayback() {
    player.stop()
    try? AVAudioSession.sharedInstance().setActive(
        false, options: .notifyOthersOnDeactivation
    )
}
```

## System Signals

### Low Power Mode

```swift
if ProcessInfo.processInfo.isLowPowerModeEnabled {
    reduceEnergyUsage()
}

NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
    .sink { [weak self] _ in
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            self?.reduceEnergyUsage()
        } else {
            self?.restoreNormalOperation()
        }
    }
    .store(in: &cancellables)
```

Reduce: pause optional work, increase timer intervals, reduce animation frame rates, defer network, stop non-critical location.

### Thermal State

```swift
NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
    .sink { [weak self] _ in
        switch ProcessInfo.processInfo.thermalState {
        case .nominal, .fair:
            self?.restoreNormalOperation()
        case .serious:
            self?.reduceGPUWork()
            self?.pauseBackgroundTasks()
        case .critical:
            self?.minimumViableOperation()
        @unknown default:
            break
        }
    }
    .store(in: &cancellables)
```

### Energy-Aware URLSession

```swift
let config = URLSessionConfiguration.background(withIdentifier: "com.app.sync")
config.isDiscretionary = true                  // System picks optimal time
config.allowsExpensiveNetworkAccess = false     // WiFi only
config.waitsForConnectivity = true             // No failed connection attempts
```

For background task scheduling with `requiresExternalPower` and EMRCA principles, see `ios-background-tasks`.

## Production Monitoring

### MetricKit

```swift
import MetricKit

class EnergyMetrics: NSObject, MXMetricManagerSubscriber {
    func startMonitoring() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            if let cpu = payload.cpuMetrics {
                log("foreground_cpu", cpu.cumulativeCPUTime)
            }
            if let location = payload.locationActivityMetrics {
                log("bg_location", location.cumulativeBackgroundLocationTime)
            }
        }
    }
}
```

Also check **Xcode Organizer > Battery Usage** for field data: foreground/background breakdown, category breakdown, version comparison.

## Audit Checklists

### Timers
- [ ] All timers have tolerance >= 10% of interval
- [ ] Timers invalidated when no longer needed
- [ ] Timers stopped on background entry
- [ ] No polling patterns that could use push

### Network
- [ ] Requests batched, not many small ones
- [ ] `isDiscretionary = true` for non-urgent downloads
- [ ] `waitsForConnectivity = true` set
- [ ] `allowsExpensiveNetworkAccess = false` for deferrable work
- [ ] Push notifications instead of polling

### Location
- [ ] Accuracy matches use case (not `Best` unless navigation)
- [ ] `distanceFilter` set to reduce updates
- [ ] Updates stopped when no longer needed
- [ ] Significant-change for background
- [ ] Background location justified

### GPU/Display
- [ ] Dark Mode supported
- [ ] Animations stopped when view not visible
- [ ] Secondary animations use appropriate frame rates
- [ ] Blur effects minimized

### Disk I/O
- [ ] Writes batched, not frequent small writes
- [ ] SQLite using WAL journaling
- [ ] No rapid file creation/deletion cycles

## Key Savings Reference

| Optimization | Potential Savings |
|---|---|
| Dark Mode on OLED | Up to 70% display power |
| Frame rate alignment | Up to 20% GPU power |
| Push vs poll | ~100x network efficiency |
| Location accuracy reduction | 50-90% GPS power |
| Timer tolerance | Significant CPU savings |
| Lazy loading | Eliminates startup CPU spikes |

## WWDC Sessions

- WWDC25-226: Profile and optimize power usage in your app
- WWDC25-227: Finish tasks in the background
- WWDC22-10083: Power down: Improve battery consumption
- WWDC20-10095: The Push Notifications primer
- WWDC19-417: Improving Battery Life and Performance
