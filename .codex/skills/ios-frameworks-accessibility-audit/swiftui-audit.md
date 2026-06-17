# SwiftUI Accessibility Audit Reference

**Platforms:** iOS, iPadOS, macOS
**Framework:** SwiftUI

This file contains SwiftUI-specific accessibility patterns, common mistakes, and patch-ready fix templates. Use it when auditing SwiftUI views.

---

## VoiceOver Semantics

### Labels

- Icon-only buttons **must** have an `accessibilityLabel`.
- Do **not** add `accessibilityLabel` when the view already displays meaningful text — SwiftUI derives the label automatically.
- Use `accessibilityLabel` to *replace* a bad automatic label, not to duplicate a good one.

**Bad — redundant label:**
```swift
Button("Save") { save() }
    .accessibilityLabel("Save") // Unnecessary; "Save" is already the label
```

**Bad — missing label:**
```swift
Button(action: save) {
    Image(systemName: "tray.and.arrow.down")
}
// VoiceOver reads "tray.and.arrow.down" or nothing useful
```

**Good — label on icon-only button:**
```swift
Button(action: save) {
    Image(systemName: "tray.and.arrow.down")
        .accessibilityLabel("Save")
}
```

### Hints

- Use `accessibilityHint` only when it adds real "how to interact" context.
- Never repeat the label in the hint.

### Traits

- Use `accessibilityAddTraits(.isButton)` on tappable views that are not already `Button`.
- Use `accessibilityAddTraits(.isHeader)` on section headers.
- Use `accessibilityRemoveTraits` to correct inferred traits that are wrong.

### Grouping and Reading Order

- Use `accessibilityElement(children: .combine)` to merge related views into one VoiceOver stop.
- Use `accessibilityElement(children: .ignore)` with a custom label when children produce a confusing reading.
- Prefer `accessibilityElement(children: .contain)` only when children should remain individually focusable.

**Bad — tappable row with too many VoiceOver stops:**
```swift
HStack(spacing: 12) {
    Image(systemName: "sparkles")
    VStack(alignment: .leading) {
        Text("Pro Plan")
        Text("Renews monthly")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}
.onTapGesture { openPlanDetails() }
```

**Good — grouped, labelled, with correct trait:**
```swift
HStack(spacing: 12) {
    Image(systemName: "sparkles")
        .accessibilityHidden(true)
    VStack(alignment: .leading) {
        Text("Pro Plan")
        Text("Renews monthly")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}
.onTapGesture { openPlanDetails() }
.contentShape(Rectangle())
.accessibilityElement(children: .combine)
.accessibilityAddTraits(.isButton)
.accessibilityLabel("Pro Plan")
.accessibilityHint("Opens plan details")
```

### Hiding Decorative Elements

- Use `accessibilityHidden(true)` on purely decorative images and dividers.
- Use `Image(decorative:)` for images that should never be announced.

---

## Dynamic Type

- Never use hard-coded font sizes (e.g., `.font(.system(size: 14))`). Use text styles (`.font(.body)`, `.font(.headline)`).
- Avoid `lineLimit(1)` on content that carries meaning — it truncates at large sizes.
- Avoid blanket `minimumScaleFactor` — it silently shrinks text instead of letting layout adapt.
- Test layouts at the largest accessibility text sizes (`AX5`).

**Bad — truncation hides meaning:**
```swift
Text("€1,234.56")
    .font(.headline)
    .lineLimit(1)
```

**Good — allows wrapping:**
```swift
Text("€1,234.56")
    .font(.headline)
    .multilineTextAlignment(.trailing)
```

---

## Focus and Keyboard Navigation

- On macOS and iPadOS with keyboard, ensure all interactive elements are reachable via Tab/Shift-Tab.
- Use `@FocusState` to manage programmatic focus.
- Ensure focus order is logical — it should follow the visual layout.
- Avoid focus traps where keyboard users cannot exit a region.

---

## Colour and Contrast

- Do not rely on colour alone to convey state (error, selected, disabled).
- Prefer semantic/system colours (`Color.primary`, `Color.accentColor`) that adapt to appearance settings.
- Pair colour with an icon, text label, or VoiceOver cue to reinforce meaning.

---

## Touch Targets (iOS)

- Tappable elements should be at least 44x44 pt.
- Use `.contentShape(Rectangle())` or padding to expand hit areas without changing visual design.
- Small icon buttons are a common P1 finding.

---

## Motion

- Check `@Environment(\.accessibilityReduceMotion)` before running animations.
- Provide a static alternative or disable animation when Reduce Motion is active.
- Avoid auto-playing animations that loop indefinitely.

---

## Common SwiftUI Mistakes (Quick Reference)

| Mistake | Severity | Fix |
|---|---|---|
| Icon-only `Button` without label | P0 | Add `.accessibilityLabel("...")` |
| `onTapGesture` without `.isButton` trait | P0 | Add `.accessibilityAddTraits(.isButton)` |
| Hard-coded `.system(size:)` font | P1 | Use `.font(.body)` or text style |
| `lineLimit(1)` on meaningful text | P1 | Remove or use `.multilineTextAlignment` |
| Decorative image announced by VoiceOver | P1 | Add `.accessibilityHidden(true)` |
| Multiple VoiceOver stops in a tappable row | P1 | Use `.accessibilityElement(children: .combine)` |
| Colour-only state indication | P1 | Add icon, text, or VoiceOver cue |
| No Reduce Motion check before animation | P2 | Check `accessibilityReduceMotion` |
| Redundant `accessibilityLabel` on `Text` view | P2 | Remove the modifier |

---

## References

- [Accessibility in SwiftUI](https://developer.apple.com/documentation/swiftui/accessibility)
- [Supporting Dynamic Type](https://developer.apple.com/documentation/swiftui/dynamic-type)
- [Apple HIG - Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
