# Widget Debugging Guide

## Troubleshooting Decision Tree

```
Widget/Extension Issue?
|
+-- Widget not appearing in gallery?
|   +-- WidgetBundle includes this widget? (@main)
|   +-- supportedFamilies() declared?
|   +-- Extension target "Skip Install" = NO?
|   +-- Extension embedded in app (Embed App Extensions)?
|   +-- Clean build folder (Cmd+Shift+K), restart Xcode
|
+-- Widget not refreshing?
|   +-- Timeline policy set to .never?
|   |   +-- Change to .atEnd or .after(date)
|   +-- Budget exhausted? (too frequent reloads)
|   |   +-- Increase interval between entries (15-60 min)
|   +-- getTimeline() completing? (add print() logging)
|   +-- Manual reload test:
|       +-- WidgetCenter.shared.reloadAllTimelines()
|       +-- If this fixes it -> problem is timeline policy or budget
|
+-- Widget shows empty/old data?
|   +-- App Groups configured in BOTH targets?
|   |   +-- No -> Add "App Groups" entitlement to both
|   |   +-- Yes -> Verify identical group identifier string
|   +-- Using UserDefaults.standard in extension?
|   |   +-- Change to UserDefaults(suiteName: "group.com.myapp")
|   +-- Shared container path valid?
|       +-- Print containerURL in both targets, verify not nil
|       +-- Paths must match between app and extension
|
+-- Interactive button not working? (iOS 17+)
|   +-- Using Button(intent:), not Button(action:)?
|   +-- App Intent perform() returns IntentResult?
|   +-- perform() updates shared App Group storage?
|   +-- perform() calls WidgetCenter.reloadTimelines()?
|   +-- Intent target membership includes widget extension?
|
+-- Live Activity fails to start?
|   +-- NSSupportsLiveActivities = YES in Info.plist?
|   +-- ActivityAuthorizationInfo().areActivitiesEnabled?
|   +-- ActivityAttributes + ContentState < 4 KB?
|   +-- Too many concurrent activities? (limit ~5)
|   +-- pushType correct? (nil for local, .token for push)
|
+-- Control Center control unresponsive?
|   +-- Blocking sync call in view? -> Use ControlValueProvider
|   +-- previewValue provides instant fallback?
|   +-- currentValue() async and fast (< 1 second)?
|
+-- watchOS Live Activity not showing?
    +-- supplementalActivityFamilies includes .small?
    +-- watchOS 11+ target?
    +-- Apple Watch paired and in Bluetooth range?
```

## Per-Category Debugging Checklists

### Widget Debugging

Run through these before investigating further:

1. **App Groups accessible?**
   ```swift
   let container = FileManager.default.containerURL(
       forSecurityApplicationGroupIdentifier: "group.com.myapp"
   )
   print("Container: \(container?.path ?? "NIL")")
   // Must print valid path in BOTH app and extension
   ```

2. **Timeline being generated?**
   ```swift
   func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
       print("[Widget] getTimeline called at \(Date())")
       // ... existing code ...
       print("[Widget] Returning \(entries.count) entries")
       completion(timeline)
   }
   ```

3. **Widget registered?**
   ```swift
   WidgetCenter.shared.getCurrentConfigurations { result in
       switch result {
       case .success(let configs):
           for config in configs {
               print("Widget: \(config.kind), family: \(config.family)")
           }
       case .failure(let error):
           print("Error: \(error)")
       }
   }
   ```

4. **Simulator vs device?**
   - Simulator: no budget limits, no push, no memory enforcement, instant refreshes
   - Device: budget-limited (40-70/day), real memory limits, real refresh timing
   - Always verify on device before shipping

### Live Activity Debugging

1. **Size check** — Encode attributes + state, verify < 4096 bytes
2. **Authorization** — `ActivityAuthorizationInfo().areActivitiesEnabled` must be true
3. **Info.plist** — `NSSupportsLiveActivities` = YES
4. **Push token** — If using push, observe `activity.pushTokenUpdates` and verify token reaches server
5. **Dismissal** — Every code path that completes the event must call `activity.end(_:dismissalPolicy:)`

### Control Center Control Debugging

1. **Async data** — `ControlValueProvider` with async `currentValue()`, never blocking calls in view
2. **Preview fallback** — `previewValue` returns cached state instantly
3. **Intent execution** — `perform()` is async, updates cache optimistically, then syncs real state
4. **Reload** — After intent completes, widget system refreshes the control automatically

## Widget Not Appearing in Gallery (Common Causes)

| Cause | Fix |
|---|---|
| Widget not in `WidgetBundle` | Add widget type to `@main` bundle's `body` |
| Missing `supportedFamilies()` | Add `.supportedFamilies([...])` to configuration |
| Extension "Skip Install" = YES | Set to NO in build settings |
| Extension not embedded | Target -> General -> Frameworks, Libraries, and Embedded Content |
| Stale build cache | Clean Build Folder (Cmd+Shift+K), delete derived data, restart Xcode |
| Deployment target mismatch | Extension deployment target must match or be lower than app |
