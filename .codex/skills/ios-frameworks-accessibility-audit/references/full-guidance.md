# Apple Accessibility Auditor

**Platforms:** iOS, iPadOS, macOS
**Frameworks:** SwiftUI, UIKit, AppKit
**Category:** Accessibility
**Output style:** Prioritised findings (P0/P1/P2) + patch-ready code + manual testing checklist

## Responsibility

**Owns:**
- Accessibility auditing across all Apple UI frameworks (SwiftUI, UIKit, AppKit)
- VoiceOver semantics: labels, traits/roles, hints, values, reading order, grouping
- Dynamic Type and text scaling compliance
- Colour contrast and non-colour affordances
- Keyboard and switch control navigation
- Touch/click target sizing
- Motion preferences (Reduce Motion)
- Semantic reasoning about UI intent
- Assistive Access scene and simplified UI patterns (iOS 17+)

**Does NOT own:**
- Human Interface Guidelines design rules (visual style, layout aesthetics)
- View construction or architecture decisions
- UX flow analysis or information architecture
- UI testing infrastructure (accessibility identifiers for XCTest are out of scope unless they aid auditing)

## Core Principles

1. **Reason about semantics first.** Understand what a control *means* before deciding what modifiers it needs. A button that already has visible text does not need a redundant `accessibilityLabel`. A decorative image should be hidden, not labelled.

2. **Use the right platform auditor.** SwiftUI, UIKit, and AppKit have different APIs and different conventions. Never suggest UIKit APIs in SwiftUI code or vice versa. Consult the platform-specific reference file.

3. **Prioritise findings as P0 / P1 / P2.**
   - **P0 (Blocker):** Prevents core functionality with assistive technology. Examples: an unlabelled primary action button, a screen unreachable by keyboard, a custom control invisible to VoiceOver.
   - **P1 (High):** Significantly degrades the experience. Examples: confusing reading order, text that truncates at large Dynamic Type sizes, state not discoverable via VoiceOver.
   - **P2 (Low):** Polish and consistency. Examples: a hint that could be clearer, grouping that would reduce VoiceOver stops, a semantic colour substitution.

4. **Provide patch-ready suggestions.** Every finding must include a concrete code fix that can be applied directly. Prefer minimal diffs. Specify where the code belongs (e.g., `viewDidLoad`, modifier chain, `init`).

5. **Accessibility is not a checklist.** Do not mechanically apply modifiers. Every change must have a clear justification rooted in how an assistive technology user would experience the interface.

6. **Respect constraints.** Do not rewrite architecture, change user-facing copy, or break layout unless it is the only way to resolve an accessibility blocker. Prefer minimal, localised, safe changes.

7. **Cross-platform when possible.** When auditing SwiftUI code that runs on both iOS and macOS, flag platform-specific concerns (e.g., touch targets on iOS, key view loop on macOS) and keep fixes portable where feasible.

8. **Assistive Access is a separate scene, not a toggle.** If the app serves users with cognitive disabilities, provide an `AssistiveAccess { }` scene with a flat, simplified UI. See `references/assistive-access.md`.

## First-Draft Accessibility Rules

Accessibility is not a retrofit. Every UI element must include accessibility code in its first draft. Use this table when writing new code.

### Required Accessibility by UI Pattern

| UI Pattern | Required Accessibility Code | Example |
|---|---|---|
| Icon-only button | `.accessibilityLabel("descriptive action")` | `Button { } label: { Image(systemName: "trash") }.accessibilityLabel("Delete item")` |
| Decorative image | `.accessibilityHidden(true)` | `Image("background-pattern").accessibilityHidden(true)` |
| Informational image | `.accessibilityLabel("description")` | `Image("chart-trend-up").accessibilityLabel("Trending upward this week")` |
| Custom toggle/switch | `.accessibilityAddTraits(.isToggle)` + `.accessibilityValue(isOn ? "On" : "Off")` | — |
| Custom slider/stepper | `.accessibilityValue` + `.accessibilityAdjustableAction` | Provide increment/decrement actions |
| Grouped content (card) | `.accessibilityElement(children: .combine)` or manual label | Combine card title + subtitle + value into one VoiceOver stop |
| `onTapGesture` on non-Button | Wrap in `Button` instead, or add `.accessibilityAddTraits(.isButton)` | Prefer `Button` — it gets keyboard and switch control for free |
| `withAnimation` / motion | Provide `@Environment(\.accessibilityReduceMotion)` alternative | Crossfade instead of slide, or skip animation entirely |
| Custom progress indicator | `.accessibilityValue("\(Int(progress * 100)) percent")` | Keep value updated as progress changes |
| Tab-like custom control | `.accessibilityAddTraits(.isTabBar)` on container | Each tab gets `.accessibilityAddTraits(.isSelected)` when active |
| Drag-and-drop reorderable list | `.accessibilityAction(.move)` or accessibility rotor | Provide non-gesture reorder mechanism |
| Time-sensitive content (toast/snackbar) | `.accessibilityLiveRegion(.polite)` or post announcement | `AccessibilityNotification.Announcement("Item saved").post()` |

### `// TODO: [VERIFY]` Comments

When an accessibility label is **inferred** rather than explicitly confirmed (e.g., derived from an SF Symbol name, a variable name, or surrounding context), tag it with `// TODO: [VERIFY]`:

```swift
Image(systemName: "heart.fill")
    .accessibilityLabel("Favorites") // TODO: [VERIFY] — inferred from symbol name, confirm with design
```

SF Symbol names rarely match user intent. "heart.fill" might mean "Favorites", "Liked", "Health", or "Save". The `// TODO: [VERIFY]` comment ensures a human confirms the label before shipping.

**Rule:** Every inferred accessibility label gets `// TODO: [VERIFY]`. Every explicitly provided label (from a spec, design, or user instruction) does not.

## Audit Workflow

1. **Identify the framework.** Determine whether the code is SwiftUI, UIKit, or AppKit, then consult the corresponding reference file.

2. **Read the UI semantically.** Before scanning for missing modifiers, understand the screen's purpose, the user's primary task, and the intended interaction model.

3. **Audit against the platform checklist.** Walk through the relevant reference file's checklist areas: VoiceOver semantics, Dynamic Type, keyboard/focus, colour/contrast, touch targets, motion, and announcements.

4. **Classify findings.** Assign P0/P1/P2 to each issue. Group by priority in the output.

5. **Write patch-ready fixes.** For each finding, provide a minimal before/after diff or code snippet. Never invent APIs that do not exist.

6. **Append a manual testing checklist.** Provide 4-8 concrete verification steps the developer can perform with VoiceOver, Dynamic Type settings, and keyboard navigation.

### Output Format

```
### Findings
- **P0:** [description] — [why it matters]
- **P1:** [description] — [why it matters]
- **P2:** [description] — [why it matters]

### Suggested Patch
\```diff
- old code
+ new code
\```

### Manual Testing Checklist
- [ ] VoiceOver: ...
- [ ] Dynamic Type: ...
- [ ] Keyboard: ...
- [ ] Colour/contrast: ...
```

## References

Platform-specific audit rules and patterns:

- [SwiftUI Audit Reference](swiftui-audit.md) — SwiftUI accessibility patterns, VoiceOver, Dynamic Type, common mistakes
- [UIKit Audit Reference](uikit-audit.md) — UIAccessibility API, trait collections, custom controls, Dynamic Type
- [AppKit Audit Reference](appkit-audit.md) — NSAccessibility, keyboard navigation, tables/outline views, macOS concerns
- [Manual Testing Guide](manual-testing.md) — VoiceOver testing workflow, Dynamic Type testing, Reduce Motion verification

- [Assistive Access Reference](references/assistive-access.md) — AssistiveAccess scene, runtime detection, design guidelines

## App Store Accessibility Nutrition Label

When preparing an app for submission, generate Accessibility Nutrition Label claims for App Store Connect. The 9 categories are:

1. **VoiceOver** — all interactive elements labelled, reading order logical, custom controls exposed
2. **AssistiveTouch** — alternative input methods supported
3. **Full Keyboard Access** — all features reachable via keyboard
4. **Switch Control** — all features reachable via switch scanning
5. **Closed Captions** — media content captioned (if applicable)
6. **Audio Descriptions** — visual content described in audio (if applicable)
7. **Dynamic Type** — all text scales with system text size preference
8. **Reduce Motion** — motion-sensitive animations have alternatives
9. **Increase Contrast** — UI adapts to increased contrast preference

For each category, verify with a concrete test (e.g., "Navigate the entire main flow with VoiceOver — every screen reachable, every action performable"). Only claim categories that pass verification.

See also: `app-store-release` for the full App Store submission checklist.

External references:

- [Apple HIG - Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Accessibility in SwiftUI](https://developer.apple.com/documentation/swiftui/accessibility)
- [UIKit Accessibility](https://developer.apple.com/documentation/uikit/accessibility)
- [AppKit Accessibility](https://developer.apple.com/documentation/appkit/accessibility)
