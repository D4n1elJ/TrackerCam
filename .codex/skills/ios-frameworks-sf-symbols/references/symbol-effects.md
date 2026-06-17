# SF Symbols -- Effects & Rendering Reference

Complete API reference for SF Symbols rendering modes, effects, Draw animations, and custom symbols. All examples target iOS 26+ in SwiftUI.

---

## Effect Categories

Every symbol effect belongs to one of four behavioral categories:

| Category | Protocol | Trigger | Duration | Modifier |
|---|---|---|---|---|
| Discrete | `DiscreteSymbolEffect` | `value:` (Equatable) | One-shot | `.symbolEffect(_:options:value:)` |
| Indefinite | `IndefiniteSymbolEffect` | `isActive:` (Bool) | Loops while true | `.symbolEffect(_:options:isActive:)` |
| Transition | `TransitionSymbolEffect` | View lifecycle | On insert/remove | `.transition(.symbolEffect(_:))` |
| Content Transition | `ContentTransitionSymbolEffect` | Symbol name change | One-shot | `.contentTransition(.symbolEffect(_:))` |

---

## All Effects

### Bounce

**Category**: Discrete

Brief springy animation. The go-to for tap feedback.

```swift
Image(systemName: "arrow.down.circle")
    .symbolEffect(.bounce, value: downloadCount)
```

**Variants**:
- `.bounce.up` / `.bounce.down` -- directional
- `.bounce.byLayer` -- layers bounce at staggered times
- `.bounce.wholeSymbol` -- entire symbol bounces together

---

### Pulse

**Category**: Discrete, Indefinite

Subtle opacity pulsing. Best for "waiting" states.

```swift
// Indefinite
Image(systemName: "network")
    .symbolEffect(.pulse, isActive: isConnecting)

// Discrete
Image(systemName: "exclamationmark.triangle")
    .symbolEffect(.pulse, value: errorCount)
```

**Variants**: `.pulse.byLayer`, `.pulse.wholeSymbol`

---

### Variable Color

**Category**: Discrete, Indefinite

Iterates through symbol layers, highlighting each in sequence.

```swift
Image(systemName: "wifi")
    .symbolEffect(.variableColor.iterative, isActive: isSearching)
```

**Variants**:
- `.variableColor.iterative` -- one layer at a time
- `.variableColor.cumulative` -- progressively fills
- `.variableColor.iterative.reversing` -- cycles back and forth
- `.variableColor.iterative.hideInactiveLayers` -- dims non-highlighted fully
- `.variableColor.iterative.dimInactiveLayers` -- slightly reduces inactive opacity

---

### Scale

**Category**: Indefinite

Scales symbol up or down for emphasis.

```swift
Image(systemName: "mic.fill")
    .symbolEffect(.scale.up, isActive: isRecording)
```

**Variants**: `.scale.up`, `.scale.down`, `.scale.up.byLayer`, `.scale.up.wholeSymbol`

---

### Wiggle

**Category**: Discrete, Indefinite

Horizontal shake to draw attention.

```swift
Image(systemName: "bell.fill")
    .symbolEffect(.wiggle, value: notificationCount)
```

**Variants**:
- `.wiggle.left` / `.wiggle.right`
- `.wiggle.up` / `.wiggle.down`
- `.wiggle.forward` / `.wiggle.backward` -- RTL-aware
- `.wiggle.clockwise` / `.wiggle.counterClockwise`
- `.wiggle.custom(angle: .degrees(15))` -- custom angle
- `.wiggle.byLayer`

---

### Rotate

**Category**: Discrete, Indefinite

Single or continuous rotation. Use for mechanical/processing indicators.

```swift
// Indefinite
Image(systemName: "gear")
    .symbolEffect(.rotate, isActive: isProcessing)

// Discrete
Image(systemName: "arrow.trianglehead.2.clockwise")
    .symbolEffect(.rotate, value: refreshCount)
```

**Variants**:
- `.rotate.clockwise` / `.rotate.counterClockwise`
- `.rotate.byLayer` -- only specific layers rotate (e.g., fan blades spin, housing stays)

---

### Breathe

**Category**: Discrete, Indefinite

Smooth rhythmic scale animation -- like the symbol is breathing. Best for organic/living indicators.

```swift
Image(systemName: "heart.fill")
    .symbolEffect(.breathe, isActive: isMonitoring)
```

**Variants**:
- `.breathe.plain` -- scale only
- `.breathe.pulse` -- scale + opacity
- `.breathe.byLayer`

---

### Appear / Disappear

**Category**: Transition

Animate symbols entering or leaving the view hierarchy.

```swift
if showSymbol {
    Image(systemName: "checkmark.circle.fill")
        .transition(.symbolEffect(.appear))
}
```

**Variants**:
- `.appear.up` / `.appear.down`
- `.disappear.up` / `.disappear.down`
- `.appear.byLayer` / `.appear.wholeSymbol`

---

### Replace

**Category**: Content Transition

Animates from one symbol to another. Applies via `.contentTransition`.

```swift
Image(systemName: isFavorite ? "star.fill" : "star")
    .contentTransition(.symbolEffect(.replace))
```

**Variants**:
- `.replace.downUp` -- old moves down, new moves up
- `.replace.upUp` -- both move up
- `.replace.offUp` -- old fades, new moves up
- `.replace.byLayer` / `.replace.wholeSymbol`

---

## Magic Replace

When two symbols share structure (e.g., `star` / `star.fill`, `pause.fill` / `play.fill`), `.replace` automatically morphs shared elements while transitioning the rest. This is the default behavior.

For unrelated symbol pairs, specify an explicit fallback:

```swift
.contentTransition(.symbolEffect(.replace.magic(fallback: .replace.downUp)))
```

On iOS 26+, Magic Replace can combine with Draw effects -- the shared enclosure (like a circle outline) stays while inner elements transition with draw animations.

---

## Effect Options

All effects accept `SymbolEffectOptions`:

```swift
// Repeat count
.symbolEffect(.bounce, options: .repeat(3), value: count)

// Speed multiplier
.symbolEffect(.pulse, options: .speed(2.0), isActive: true)

// Continuous repeat
.symbolEffect(.variableColor, options: .repeat(.continuous), isActive: true)

// Non-repeating (run once then hold)
.symbolEffect(.breathe, options: .nonRepeating, isActive: true)

// Combined
.symbolEffect(.wiggle, options: .repeat(5).speed(1.5), value: count)
```

### Remove All Effects

```swift
Image(systemName: "star.fill")
    .symbolEffectsRemoved()
```

---

## Draw On / Draw Off (iOS 26+)

Draw animations simulate hand-drawing a symbol stroke by stroke. The signature feature of SF Symbols 7.

### Draw On

Symbol "draws in" when activated.

```swift
Image(systemName: "checkmark.circle")
    .symbolEffect(.drawOn, isActive: isComplete)
```

### Draw Off

Symbol "erases out" when activated.

```swift
Image(systemName: "star.fill")
    .symbolEffect(.drawOff, isActive: isHidden)
```

### Playback Modes

Control how multi-layer symbols sequence their draw animation:

| Mode | Behavior | Best For |
|---|---|---|
| `.byLayer` (default) | Staggered timing, layers overlap | Most symbols -- natural feel |
| `.wholeSymbol` | All layers draw simultaneously | Symbol should appear as one unit |
| `.individually` | Sequential, each layer finishes before next starts | Storytelling, onboarding emphasis |

```swift
Image(systemName: "square.and.arrow.up")
    .symbolEffect(.drawOn.byLayer, isActive: showIcon)

Image(systemName: "square.and.arrow.up")
    .symbolEffect(.drawOn.wholeSymbol, isActive: showIcon)

Image(systemName: "square.and.arrow.up")
    .symbolEffect(.drawOn.individually, isActive: showIcon)
```

### Draw Off Direction

```swift
// Forward (default) -- follows the draw path
.symbolEffect(.drawOff.nonReversed, isActive: isHidden)

// Reversed -- erases in reverse order
.symbolEffect(.drawOff.reversed, isActive: isErasing)
```

---

## Variable Draw vs Variable Color

Two ways to use `variableValue:` on a symbol -- they are mutually exclusive at render time.

| Mode | Modifier | What It Does | Available |
|---|---|---|---|
| Variable Color | `.symbolVariableValueMode(.color)` (default) | Sets layer opacity on/off based on value threshold | iOS 17+ |
| Variable Draw | `.symbolVariableValueMode(.draw)` | Draws stroke proportional to value (0-1) | iOS 26+ |

```swift
// Variable Color -- layers light up as value increases
Image(systemName: "wifi", variableValue: signalStrength)
    .symbolVariableValueMode(.color)

// Variable Draw -- stroke draws proportionally
Image(systemName: "thermometer.high", variableValue: temperature)
    .symbolVariableValueMode(.draw)
```

Setting an unsupported mode on a symbol has no visible effect. Check the SF Symbols app to confirm support.

---

## Gradient Rendering (iOS 26+)

Automatic gradient fill from a single source color using `SymbolColorRenderingMode`.

```swift
Image(systemName: "heart.fill")
    .symbolColorRenderingMode(.gradient)
    .foregroundStyle(.red)
```

| Mode | Description |
|---|---|
| `.flat` (default) | Solid color fill |
| `.gradient` | Axial gradient generated from source color |

Works with all rendering modes. Most effective at larger symbol sizes.

```swift
// Gradient + Hierarchical
Image(systemName: "cloud.rain.fill")
    .symbolRenderingMode(.hierarchical)
    .symbolColorRenderingMode(.gradient)
    .foregroundStyle(.blue)
```

---

## Custom Symbol Draw Annotation

To enable Draw animations on custom symbols, annotate paths in the SF Symbols 7 app:

1. Open your custom symbol template
2. Select a path layer
3. Add guide points to define draw direction:

| Point Type | Visual | Purpose |
|---|---|---|
| Start | Open circle | Where drawing begins |
| End | Closed circle | Where drawing ends |
| Corner | Diamond | Sharp direction change |
| Bidirectional | Double arrow | Center-outward drawing |
| Attachment | Link icon | Non-drawing decorative connection |

4. Minimum: 2 guide points per path (start + end)
5. Option-drag for precise placement
6. Test in Preview panel across all weight variants

**Troubleshooting**: If `.symbolEffect(.drawOn)` does nothing on your custom symbol:
- Confirm guide points are placed on stroked paths, not fills
- Confirm at least 2 guide points per path
- Confirm you are using SF Symbols 7+ app
- Each annotatable layer needs its own guide points

---

## Custom Symbol Weight Variants

Custom symbols need designs for at least 3 weights:
- **Ultralight** (thinnest)
- **Regular** (middle)
- **Black** (thickest)

The system interpolates intermediate weights (Thin, Light, Medium, Semibold, Bold, Heavy).

Import to Xcode via Asset Catalog > **+** > **Symbol Image Set**, then drag the exported `.svg`.

Use `Image("mySymbolName")` for asset catalog symbols, or `Image("mySymbolName", bundle: .module)` for package resources.

---

## Platform Availability Matrix

### Rendering Modes

| Feature | iOS | macOS | watchOS | tvOS | visionOS |
|---|---|---|---|---|---|
| Monochrome | 13+ | 11+ | 6+ | 13+ | 1+ |
| Hierarchical | 15+ | 12+ | 8+ | 15+ | 1+ |
| Palette | 15+ | 12+ | 8+ | 15+ | 1+ |
| Multicolor | 15+ | 12+ | 8+ | 15+ | 1+ |
| Variable Value | 16+ | 13+ | 9+ | 16+ | 1+ |

### Symbol Effects

| Effect | Category | iOS | macOS | watchOS | tvOS | visionOS |
|---|---|---|---|---|---|---|
| Bounce | Discrete | 17+ | 14+ | 10+ | 17+ | 1+ |
| Pulse | Discrete/Indefinite | 17+ | 14+ | 10+ | 17+ | 1+ |
| Variable Color | Discrete/Indefinite | 17+ | 14+ | 10+ | 17+ | 1+ |
| Scale | Indefinite | 17+ | 14+ | 10+ | 17+ | 1+ |
| Appear | Transition | 17+ | 14+ | 10+ | 17+ | 1+ |
| Disappear | Transition | 17+ | 14+ | 10+ | 17+ | 1+ |
| Replace | Content Transition | 17+ | 14+ | 10+ | 17+ | 1+ |
| Wiggle | Discrete/Indefinite | 18+ | 15+ | 11+ | 18+ | 2+ |
| Rotate | Discrete/Indefinite | 18+ | 15+ | 11+ | 18+ | 2+ |
| Breathe | Discrete/Indefinite | 18+ | 15+ | 11+ | 18+ | 2+ |
| Draw On | Indefinite | 26+ | Tahoe+ | 26+ | 26+ | 26+ |
| Draw Off | Indefinite | 26+ | Tahoe+ | 26+ | 26+ | 26+ |
| Variable Draw | Value-based | 26+ | Tahoe+ | 26+ | 26+ | 26+ |
| Gradient Fill | Rendering | 26+ | Tahoe+ | 26+ | 26+ | 26+ |

---

## Accessibility

### Labels

```swift
// Standalone symbol -- always needs a label
Image(systemName: "star.fill")
    .accessibilityLabel("Favorite")

// Label component -- accessibility is automatic
Label("Settings", systemImage: "gear")
```

### Reduce Motion

Symbol effects automatically respect Reduce Motion. When enabled:
- Most effects are simplified or suppressed
- Replace transitions use crossfade instead of directional movement
- Indefinite effects may become static

Do not override this. If an effect carries semantic meaning, provide a text label:

```swift
Image(systemName: "wifi")
    .symbolEffect(.variableColor.iterative, isActive: isSearching)
    .accessibilityLabel(isSearching ? "Searching for WiFi" : "WiFi connected")
```

### Dynamic Type

Symbols sized with `.font()` scale automatically. Explicit point sizes do not.

```swift
// Scales with Dynamic Type
Image(systemName: "star.fill").font(.title)

// Fixed -- does NOT scale
Image(systemName: "star.fill").font(.system(size: 24))
```
