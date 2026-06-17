# Haptics Quick Reference

## Purpose

Opinionated guide for choosing the right haptic API tier, designing feedback that feels intentional, and avoiding overuse. iOS 17+ SwiftUI-first, with UIKit and Core Haptics tiers when you need them.

## How to Use

1. **Apply the design framework** (Causality-Harmony-Utility) to decide IF haptics belong
2. **Pick the API tier** using the decision tree below
3. **Check anti-patterns** before shipping
4. **For full API details**, read `references/haptic-patterns.md`

## Design Framework: Causality-Harmony-Utility

Three principles from Apple's audio and haptic design team (WWDC 2021/10278). Apply all three before writing code.

### Causality -- Make it obvious what caused the feedback

The haptic must fire at the exact moment of the interaction. A 100ms delay breaks the mental link between action and response.

- Ball hits wall -> haptic fires at collision frame
- Toggle flips -> haptic fires on state change, not on animation completion
- Slider crosses threshold -> haptic fires at the crossing point

### Harmony -- Senses reinforce each other

Visual weight, audio pitch, and haptic intensity should agree. A large object should feel heavy, sound low, and look substantial.

- Small element -> `.light` impact + high-pitched sound
- Large element -> `.heavy` impact + low-pitched sound
- Destructive action -> `.error` notification (not `.success`)

### Utility -- Provide clear value to the user

Reserve haptics for moments that genuinely help. If removing the haptic would not change the user's understanding or confidence, skip it.

**Use haptics for**:
- Confirming important actions (payment completed, item deleted)
- Alerting to state changes the user needs to notice (error, threshold crossed)
- Continuous positional feedback (scrubbing, alignment snapping)
- Milestone moments (goal reached, level completed)

**Skip haptics for**:
- Every single tap in the app
- Scrolling through content
- Background events the user cannot see
- Decorative animations with no user-initiated cause

## API Tier Decision Tree

```
Is it a standard SwiftUI view interaction?
  YES -> .sensoryFeedback() modifier (Tier 1)
  NO  -> Do you need precise timing or prepare()?
           YES -> UIFeedbackGenerator (Tier 2)
           NO  -> Do you need custom waveforms, looping, or audio sync?
                    YES -> Core Haptics / AHAP (Tier 3)
                    NO  -> UIFeedbackGenerator (Tier 2)
```

| Tier | API | When to Use |
|---|---|---|
| 1 -- SwiftUI | `.sensoryFeedback()` | Standard view interactions in SwiftUI. Simplest, declarative, no lifecycle management |
| 2 -- UIKit | `UIFeedbackGenerator` | Need `prepare()` timing, UIKit views, or intensity control |
| 3 -- Core Haptics | `CHHapticEngine` + AHAP | Custom waveforms, looping patterns, audio-haptic sync, dynamic parameters |

## SwiftUI .sensoryFeedback() at a Glance (iOS 17+)

The declarative approach. Attach to any view, trigger on value change or condition.

```swift
// Trigger on value change
Button("Save") { save() }
    .sensoryFeedback(.success, trigger: saveCount)

// Trigger on condition becoming true
ContentView()
    .sensoryFeedback(.error, trigger: showError) { old, new in new }

// Selection ticks in a picker-like control
ForEach(items) { item in
    ItemRow(item)
        .sensoryFeedback(.selection, trigger: selectedItem) { _, new in new == item }
}
```

**All SensoryFeedback cases**:

| Case | Maps To | Use For |
|---|---|---|
| `.success` | Notification success | Task completed, save confirmed |
| `.warning` | Notification warning | Approaching limit, needs attention |
| `.error` | Notification error | Validation failure, action blocked |
| `.selection` | Selection changed | Picker tick, segment change, discrete step |
| `.increase` | Impact (light) | Value going up, volume increase |
| `.decrease` | Impact (light) | Value going down, volume decrease |
| `.start` | Impact (medium) | Recording began, timer started |
| `.stop` | Impact (medium) | Recording ended, timer stopped |
| `.alignment` | Impact (rigid) | Snap to guide, grid alignment |
| `.levelChange` | Impact (medium) | Threshold crossed, level transition |
| `.impact` | Impact (medium) | General physical collision or tap |

## Anti-Patterns

| Mistake | Fix |
|---|---|
| Haptic on every list row tap | Reserve for meaningful state changes; row navigation needs no haptic |
| `.success` for destructive actions | Use `.warning` or `.error` to match the emotional weight |
| Haptic during scroll | Scrolling is continuous and passive; only fire on snap points or thresholds |
| Creating a new `UIFeedbackGenerator` per event | Reuse the instance; create once, call `prepare()` on touchDown |
| Forgetting `prepare()` in UIKit | Call `prepare()` ~1 second before the expected haptic to eliminate latency |
| Core Haptics without `stoppedHandler` / `resetHandler` | Engine can be interrupted by calls or Siri; always handle restart |
| Testing only in Simulator | Haptics produce no output in Simulator; always verify on a physical device |
| Ignoring accessibility | Users can disable System Haptics; UIFeedbackGenerator respects this automatically, but Core Haptics does not -- check `CHHapticEngine.capabilitiesForHardware().supportsHaptics` |

## When NOT to Use Haptics

These are firm rules, not suggestions:

1. **No haptic for passive content consumption** -- reading, scrolling, browsing
2. **No haptic for navigation** -- pushing/popping views, switching tabs
3. **No haptic for animations the user did not cause** -- auto-refresh, background sync
4. **No haptic in rapid succession** -- debounce to at minimum 50ms between fires
5. **No Core Haptics when UIFeedbackGenerator suffices** -- simpler API, lower battery cost, respects system settings automatically

## Hardware & Testing

- **Physical device required** -- Simulator runs the code silently with no output
- **iPhone 8+** required for Core Haptics; all iPhones support UIFeedbackGenerator
- Test with System Haptics disabled (Settings -> Sounds & Haptics)
- Test in Low Power Mode (haptics may be suppressed)
- Test during interruptions (incoming call stops CHHapticEngine)
- Profile battery impact with Instruments Energy Log

## Full Reference

For the complete API -- all UIFeedbackGenerator subclasses, Core Haptics engine lifecycle, AHAP file structure, CHHapticAdvancedPatternPlayer looping, dynamic parameters, audio constraints, and synchronized playback -- read `references/haptic-patterns.md`.

## Global Rules

| Rule | Value |
|---|---|
| Default API tier | `.sensoryFeedback()` in SwiftUI, `UIFeedbackGenerator` in UIKit |
| Always check before Core Haptics | `CHHapticEngine.capabilitiesForHardware().supportsHaptics` |
| Prepare timing | Call `prepare()` on touchDown; engine stays ready ~1 second |
| Audio file limits for AHAP | < 4.2 MB, < 23 seconds |
| Reduce Motion | UIFeedbackGenerator respects automatically; no extra handling needed |
| Deployment target | iOS 17+ for `.sensoryFeedback()`; iOS 13+ for Core Haptics |
