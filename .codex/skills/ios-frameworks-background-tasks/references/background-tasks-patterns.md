# Background Tasks Patterns

## Task Type Quick Reference

| Type | Runtime | When Runs | Use Case |
|---|---|---|---|
| BGAppRefreshTask | ~30s | System-scheduled | Keep content fresh |
| BGProcessingTask | Minutes | Charging/WiFi | Maintenance, ML training, cleanup |
| BGContinuedProcessingTask | Minutes | User-initiated → background | Photo export, file upload, publishing |
| BGHealthResearchTask | Minutes | System-scheduled | HealthKit data collection |
| SwiftUI `.backgroundTask` | ~30s | System-scheduled | Modern SwiftUI equivalent of BGAppRefreshTask |

## Info.plist Setup

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.app.refresh</string>
    <string>com.app.processing</string>
    <!-- iOS 26+: wildcard for dynamic identifiers -->
    <string>com.app.export.*</string>
</array>

<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>       <!-- For BGAppRefreshTask -->
    <string>processing</string>  <!-- For BGProcessingTask -->
</array>
```

## Registration (At Launch)

```swift
// In AppDelegate or @main App init
BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "com.app.refresh",
    using: nil  // nil = system-provided serial background queue
) { task in
    handleAppRefresh(task: task as! BGAppRefreshTask)
}

BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "com.app.processing",
    using: nil
) { task in
    handleProcessing(task: task as! BGProcessingTask)
}
```

## Scheduling

### App Refresh Task (~30 seconds)

```swift
func scheduleAppRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: "com.app.refresh")
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)  // No sooner than 15 min
    do {
        try BGTaskScheduler.shared.submit(request)
    } catch {
        // .notPermitted — identifier not in Info.plist
        // .tooManyPendingTaskRequests — max 1 refresh + 10 processing
        // .unavailable — background refresh disabled by user
        logger.error("Failed to schedule refresh: \(error)")
    }
}
```

### Processing Task (Minutes, Charging + WiFi)

```swift
func scheduleProcessing() {
    let request = BGProcessingTaskRequest(identifier: "com.app.processing")
    request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
    request.requiresNetworkConnectivity = true   // Default: false
    request.requiresExternalPower = false         // Default: false
    try? BGTaskScheduler.shared.submit(request)
}
```

## Handling Tasks

```swift
func handleAppRefresh(task: BGAppRefreshTask) {
    // 1. Schedule the next refresh FIRST
    scheduleAppRefresh()

    // 2. Start async work
    let fetchTask = Task {
        do {
            let data = try await fetchLatestData()
            updateLocalStore(data)
            task.setTaskCompleted(success: true)
        } catch {
            task.setTaskCompleted(success: false)
        }
    }

    // 3. Expiration handler — set BEFORE work completes
    task.expirationHandler = {
        fetchTask.cancel()
        task.setTaskCompleted(success: false)
    }
}

func handleProcessing(task: BGProcessingTask) {
    scheduleProcessing()

    let processingTask = Task {
        do {
            try await performHeavyWork()
            task.setTaskCompleted(success: true)
        } catch {
            task.setTaskCompleted(success: false)
        }
    }

    task.expirationHandler = {
        processingTask.cancel()
        task.setTaskCompleted(success: false)
    }
}
```

## BGContinuedProcessingTask (iOS 26+)

User-initiated work that needs to finish after the app is backgrounded. Unlike other background tasks, this registers **dynamically** when the user triggers the action, not at launch.

### Use Cases
- Photo/video export
- Document publishing
- File compression/upload
- Accessory firmware update

### Info.plist — Wildcard Identifiers

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.app.export.*</string>
</array>
```

### Dynamic Registration + Submission

```swift
func startExport(item: ExportItem) {
    let identifier = "com.app.export.\(item.id)"

    // Register dynamically — only when user initiates the action
    BGTaskScheduler.shared.register(
        forTaskWithIdentifier: identifier,
        using: nil
    ) { task in
        handleContinuedExport(task: task as! BGContinuedProcessingTask, item: item)
    }

    // Submit with progress UI metadata
    let request = BGContinuedProcessingTaskRequest(identifier: identifier)
    request.title = "Exporting \(item.name)"      // Shown in system UI
    request.subtitle = "0% complete"
    request.strategy = .fail                        // .fail = don't enqueue if can't continue
    // .enqueue = system queues for later (like BGProcessingTask)
    try? BGTaskScheduler.shared.submit(request)

    // Start the work in foreground
    Task { await performExport(item: item) }
}
```

### Mandatory Progress Reporting

BGContinuedProcessingTask **auto-expires if no progress updates are reported**. You must update progress periodically:

```swift
func handleContinuedExport(task: BGContinuedProcessingTask, item: ExportItem) {
    let exportTask = Task {
        for await progress in exportProgress(item) {
            // Update progress — required to prevent auto-expiration
            task.subtitle = "\(Int(progress * 100))% complete"
        }
        task.setTaskCompleted(success: true)
    }

    task.expirationHandler = {
        exportTask.cancel()
        task.setTaskCompleted(success: false)
    }
}
```

### GPU Access

```swift
// Check if GPU is available for background work
let resources = BGTaskScheduler.shared.supportedResources
if resources.contains(.gpu) {
    // Can use Metal/GPU in background
}
```

## SwiftUI .backgroundTask Modifier

Modern SwiftUI apps can use the `.backgroundTask` modifier instead of manual BGTaskScheduler registration. Key difference: **no `setTaskCompleted` needed** — the system handles it when the closure returns.

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .backgroundTask(.appRefresh("com.app.refresh")) {
                // Structured concurrency — cancellation handled automatically
                await refreshContent()
                // Implicit setTaskCompleted on return
            }
    }
}
```

### Scheduling from SwiftUI

```swift
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Text("Hello")
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    scheduleAppRefresh()
                }
            }
    }
}
```

### Cancellation with Structured Concurrency

```swift
.backgroundTask(.appRefresh("com.app.refresh")) {
    await withTaskCancellationHandler {
        await refreshContent()
    } onCancel: {
        // Clean up resources
    }
}
```

## Health Research Task

```swift
let request = BGHealthResearchTaskRequest(identifier: "com.app.healthresearch")
request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 60 * 60)
try? BGTaskScheduler.shared.submit(request)
// Requires HealthKit background delivery entitlement
```

## System Constraints & Throttling

The system controls when background tasks actually run. Seven factors affect scheduling:

| Factor | Impact |
|---|---|
| **Battery level** | Low battery reduces background execution |
| **Low Power Mode** | Severely limits all background tasks |
| **App usage patterns** | Frequently-used apps get more background time |
| **App Switcher state** | Force-quit apps get NO background execution |
| **Background App Refresh setting** | User can disable per-app in Settings |
| **System budget** | iOS maintains a global background execution budget |
| **Rate limiting** | Repeated rapid scheduling gets throttled |

### Checking System State

```swift
// Is background refresh enabled for this app?
let status = UIApplication.shared.backgroundRefreshStatus
switch status {
case .available: break        // Good to go
case .denied: break           // User disabled in Settings
case .restricted: break       // MDM or parental controls
@unknown default: break
}

// Is Low Power Mode active?
let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
```

### Key Insight

`earliestBeginDate` sets a *minimum* — you request a time window, the system decides when (or if) to run. A task scheduled for "15 minutes from now" may run hours later, or not at all if the user force-quits the app.

## Testing

### LLDB Commands

```
// Trigger task execution
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.app.refresh"]

// Force early termination (test expiration handler)
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateExpirationForTaskWithIdentifier:@"com.app.refresh"]
```

### Testing Workflow

1. Set breakpoint in task handler
2. Run LLDB simulate launch command
3. If breakpoint hits → registration is correct, any issue is in scheduling/system factors
4. If nothing happens → registration is broken (check Info.plist, identifier spelling, registration timing)

### Console.app Log Filter

```
subsystem:com.apple.backgroundtaskscheduler
```

### Check Pending Tasks

```swift
BGTaskScheduler.shared.getPendingTaskRequests { requests in
    for request in requests {
        print("\(request.identifier) — earliest: \(request.earliestBeginDate ?? Date.distantPast)")
    }
}
```

## Cancellation

```swift
// Cancel specific task
BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "com.app.refresh")

// Cancel all
BGTaskScheduler.shared.cancelAllTaskRequests()
```

## Diagnostics — Common Symptoms

### Task Never Runs

1. **Check Info.plist** — identifier must match exactly (case-sensitive). Verify `UIBackgroundModes` includes correct mode.
2. **Check registration timing** — must complete before `didFinishLaunchingWithOptions` returns.
3. **Check app state** — force-quit apps get zero background execution. Test on a real device with the app naturally backgrounded (not force-quit from App Switcher).
4. **LLDB simulate** — if the task runs via LLDB but not naturally, the issue is system scheduling (battery, usage patterns, Low Power Mode), not your code.

### Task Terminates Unexpectedly

1. **Expiration handler missing or slow** — handler must call `setTaskCompleted` promptly.
2. **`setTaskCompleted` not called in error path** — system assumes task is hung and kills it.
3. **Work exceeds runtime** — refresh tasks get ~30s, processing tasks get minutes. Chunk long work and checkpoint progress.

### Works in Development, Not Production

1. **LLDB bypasses system scheduling** — `_simulateLaunchForTaskWithIdentifier` always runs immediately regardless of battery, Low Power Mode, etc.
2. **Debug builds vs release** — Xcode-connected devices have relaxed throttling.
3. **User settings** — check `backgroundRefreshStatus`. Users may have disabled Background App Refresh.
4. **Add production logging** — log task start/complete events to your analytics to verify execution in the field.

### Duplicate Task Execution

Guard against submitting the same task multiple times:

```swift
func scheduleRefreshIfNeeded() {
    BGTaskScheduler.shared.getPendingTaskRequests { requests in
        let alreadyScheduled = requests.contains { $0.identifier == "com.app.refresh" }
        if !alreadyScheduled {
            self.scheduleAppRefresh()
        }
    }
}
```

### Expected Log Sequence

If background tasks aren't working, check Console.app for this sequence. A missing step tells you exactly where the problem is:

1. `Registered` — handler registered at launch
2. `Scheduling` — request submitted
3. `Starting` — system launched the task
4. `Work` — your code is executing
5. `Completed` — `setTaskCompleted` called
