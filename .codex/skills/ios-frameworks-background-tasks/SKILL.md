---
name: ios-frameworks-background-tasks
description: Use when scheduling, reviewing, or debugging BGTaskScheduler, background refresh, processing tasks, or SwiftUI background tasks.
---

# Background Tasks

Review and write BackgroundTasks code for correct task registration, scheduling, and execution patterns.

## Responsibility

**Owns:** BGTaskScheduler, BGAppRefreshTask, BGProcessingTask, BGContinuedProcessingTask (iOS 26), BGHealthResearchTask, SwiftUI `.backgroundTask` modifier, task registration, scheduling, expiration handlers, system constraints/throttling.

**Does NOT own:** URLSession background transfers (networking skill), push notifications (push-notifications skill), HealthKit background delivery (healthkit skill), location monitoring (core-location skill).

## Decision Tree — Which Mechanism?

```
Is the work user-initiated?
├─ YES → Does it need to continue after backgrounding?
│        ├─ YES → BGContinuedProcessingTask (iOS 26+)
│        └─ NO  → Do it in foreground, no background task needed
└─ NO → How long does the work take?
         ├─ ~30 seconds → BGAppRefreshTask
         ├─ Minutes → BGProcessingTask (constraints: charging/WiFi)
         └─ Health data → BGHealthResearchTask
```

For SwiftUI apps, prefer `.backgroundTask(.appRefresh(...))` modifier over manual BGTaskScheduler registration.

## Core Principles

1. **Register at launch, before app finishes launching.** `BGTaskScheduler.shared.register(forTaskWithIdentifier:)` must be called in `application(_:didFinishLaunchingWithOptions:)` or app init. Exception: BGContinuedProcessingTask registers dynamically when the user acts.
2. **Register identifiers in Info.plist.** Add to `BGTaskSchedulerPermittedIdentifiers`. iOS 26+ supports wildcards (`com.app.export.*`).
3. **Set expiration handlers first.** Always set `task.expirationHandler` before starting work — the system can terminate your task at any time.
4. **Call setTaskCompleted in every code path.** Always call `task.setTaskCompleted(success:)` when done — including error paths. SwiftUI `.backgroundTask` modifier handles this implicitly.
5. **Refresh tasks are short.** ~30 seconds. Use for lightweight fetches.
6. **Processing tasks run longer.** Minutes, but only when device is charging + on WiFi (configurable). CPU Monitor is disabled when `requiresExternalPower = true`.
7. **Schedule the next task inside the current one.** Background tasks don't repeat automatically.
8. **The system decides when (or if) to run.** `earliestBeginDate` is a hint, not a guarantee. 7 factors affect scheduling (see System Constraints in reference).

## Audit Checklist

### Registration
- [ ] Every identifier in code matches Info.plist `BGTaskSchedulerPermittedIdentifiers` (case-sensitive)
- [ ] `UIBackgroundModes` includes `fetch` (for refresh) and/or `processing` (for processing tasks)
- [ ] Registration happens before `application(_:didFinishLaunchingWithOptions:)` returns
- [ ] No duplicate registrations for the same identifier

### Handler
- [ ] Expiration handler is set BEFORE starting async work
- [ ] `setTaskCompleted(success:)` called in every path (success, error, expiration)
- [ ] Next task is scheduled inside the current handler
- [ ] Async work uses structured concurrency with cancellation support

## References

- `references/background-tasks-patterns.md` — Full patterns, iOS 26 continued processing, SwiftUI integration, system constraints, diagnostics
