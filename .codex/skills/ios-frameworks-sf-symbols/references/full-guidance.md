# SF Symbols Quick Reference

## Purpose

Opinionated guide for choosing rendering modes, picking the right symbol effect, and avoiding common mistakes. iOS 26+ only -- no `@available` checks needed.

## How to Use

1. **Pick the rendering mode** using the decision tree below
2. **Pick the effect** from the UX Purpose table
3. **Check anti-patterns** before shipping
4. **For full API details**, read `references/symbol-effects.md`

## Rendering Mode Decision Tree

```
Need depth from ONE color?           -> Hierarchical
Need specific colors per layer?      -> Palette
Want Apple's curated colors?         -> Multicolor
Just need a tinted icon?             -> Monochrome (default)
```

| Mode | Colors You Provide | What Happens |
|---|---|---|
| Monochrome | 1 via `.foregroundStyle` | All layers same color |
| Hierarchical | 1 via `.foregroundStyle` | Layers get auto-opacity (primary=100%, secondary~50%, tertiary~25%) |
| Palette | 2-3 via `.foregroundStyle` | Each layer gets the explicit color you specify |
| Multicolor | None | Apple's fixed curated colors; you cannot customize |

```swift
// Hierarchical -- single color, automatic depth
Image(systemName: "cloud.rain.fill")
    .symbolRenderingMode(.hierarchical)
    .foregroundStyle(.blue)

// Palette -- explicit per-layer colors
Image(systemName: "cloud.rain.fill")
    .symbolRenderingMode(.palette)
    .foregroundStyle(.white, .cyan)

// Multicolor -- Apple decides
Image(systemName: "cloud.sun.rain.fill")
    .symbolRenderingMode(.multicolor)
```

**Default choice**: Hierarchical. It gives depth with zero extra effort and works with every symbol.

## Symbol Effect Quick Reference

Pick the effect that matches your UX intent:

| UX Purpose | Effect | Trigger |
|---|---|---|
| Tap feedback | `.bounce` | `value:` change |
| Draw attention to change | `.wiggle` | `value:` change |
| Loading / in-progress | `.pulse` or `.breathe` | `isActive:` bool |
| Searching / cycling | `.variableColor.iterative` | `isActive:` bool |
| Mechanical processing | `.rotate` | `isActive:` bool |
| Emphasis / recording | `.scale.up` | `isActive:` bool |
| Symbol enters view | `.appear` | `.transition()` |
| Symbol exits view | `.disappear` | `.transition()` |
| Swap between two symbols | `.replace` | `.contentTransition()` |
| Handwritten reveal | `.drawOn` | `isActive:` bool |
| Handwritten exit | `.drawOff` | `isActive:` bool |
| Progress along path | Variable Draw | `variableValue:` 0-1 |

```swift
// Discrete -- fires once per value change
Image(systemName: "arrow.down.circle")
    .symbolEffect(.bounce, value: downloadCount)

// Indefinite -- loops while active
Image(systemName: "network")
    .symbolEffect(.pulse, isActive: isConnecting)

// Content transition -- animate between symbols
Image(systemName: isPlaying ? "pause.fill" : "play.fill")
    .contentTransition(.symbolEffect(.replace))

// Transition -- animate view insert/remove
if showCheck {
    Image(systemName: "checkmark.circle.fill")
        .transition(.symbolEffect(.appear))
}
```

## Anti-Patterns

### Wrong Rendering Mode

| Mistake | Fix |
|---|---|
| Palette with only 1 color | Use Monochrome, or provide 2-3 colors |
| Multicolor for branded icons | Use Palette with your brand colors |
| `.foregroundColor()` (deprecated) | Use `.foregroundStyle()` |
| Hierarchical for status indicators where colors carry meaning | Use Palette with semantic colors |
| Assuming all symbols support Multicolor | Check SF Symbols app; unsupported falls back to Monochrome |

### Wrong Effect

| Mistake | Fix |
|---|---|
| Bounce for loading state | Bounce is one-shot; use Pulse, Breathe, or Variable Color |
| Pulse for tap feedback | Too subtle; use Bounce |
| Rotate for organic shapes | Looks mechanical; use Breathe |
| Draw On for frequent toggles | Too dramatic; use Replace or Scale |
| Missing accessibility label | Always set `.accessibilityLabel()` on standalone symbol Images |

### Missing State Labels on Swap

```swift
// BAD -- VoiceOver reads the raw symbol name
Image(systemName: isFavorite ? "star.fill" : "star")
    .contentTransition(.symbolEffect(.replace))

// GOOD -- label reflects current state
Image(systemName: isFavorite ? "star.fill" : "star")
    .contentTransition(.symbolEffect(.replace))
    .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
```

## Common Patterns

### Notification Bell

```swift
Image(systemName: count > 0 ? "bell.badge.fill" : "bell.fill")
    .contentTransition(.symbolEffect(.replace))
    .symbolEffect(.wiggle, value: count)
    .symbolRenderingMode(.palette)
    .foregroundStyle(count > 0 ? .red : .primary, .primary)
```

### Record Button

```swift
Button { isRecording.toggle() } label: {
    Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
        .contentTransition(.symbolEffect(.replace))
        .symbolEffect(.breathe.pulse, isActive: isRecording)
        .font(.largeTitle)
        .foregroundStyle(isRecording ? .red : .primary)
}
.accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
```

### Draw-In Checkmark (iOS 26+)

```swift
Button { isComplete.toggle() } label: {
    Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
        .contentTransition(.symbolEffect(.replace))
        .symbolEffect(.drawOn, isActive: isComplete)
        .foregroundStyle(isComplete ? .green : .secondary)
}
```

## Gradient Rendering (iOS 26+)

```swift
Image(systemName: "heart.fill")
    .symbolColorRenderingMode(.gradient)
    .foregroundStyle(.red)
```

Most effective at larger sizes. Works with all rendering modes.

## Full Reference

For the complete API -- all effect variants, playback modes, Draw On/Off details, Variable Draw vs Variable Color, custom symbol workflow, and platform availability matrix -- read `references/symbol-effects.md`.

## Global Rules

| Rule | Value |
|---|---|
| Default rendering mode | Hierarchical for polished UI, Monochrome for toolbar/tab bar |
| Always provide | `.accessibilityLabel()` on standalone Image symbols |
| Symbol effects + Reduce Motion | System handles automatically; do not override |
| Dynamic Type | Use `.font(.title)` etc., not `.font(.system(size: 24))` |
| Deployment target | iOS 26+ only -- no `@available` checks |
