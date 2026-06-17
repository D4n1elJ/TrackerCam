# UIKit Accessibility Audit Reference

**Platforms:** iOS, iPadOS
**Framework:** UIKit

This file contains UIKit-specific accessibility patterns, API usage, common mistakes, and fix templates. Use it when auditing UIKit-based screens.

---

## VoiceOver: Labels, Hints, Values

### Labels

- Every actionable element must have a meaningful `accessibilityLabel`.
- Icon-only `UIBarButtonItem`s and image-based buttons are the most common offenders.
- Do not set a label that duplicates the button's `title` — UIKit already uses it.

**Common targets:**
- Navigation bar buttons with only an image
- Buttons inside table/collection view cells
- Custom "card" views that are tappable
- Badges, status pills, progress indicators

### Values

- Controls with changing state should expose `accessibilityValue`.
- Examples: a progress bar ("42%"), a rating control ("3 out of 5"), a stepper ("Quantity: 2").

### Hints

- Use `accessibilityHint` only when it adds "how to interact" context beyond the label.
- Never repeat the label content in the hint.

---

## Traits and Roles

- Apply correct `accessibilityTraits`: `.button`, `.header`, `.selected`, `.notEnabled`, `.adjustable`.
- For toggles and selectable items, ensure state is discoverable through traits (`.selected`) or `accessibilityValue`.
- Use `isAccessibilityElement = false` on containers to avoid duplicate announcements from parent and child.

**Example — bar button item without label (P0):**
```swift
// Before
navigationItem.rightBarButtonItem = UIBarButtonItem(
    image: UIImage(systemName: "square.and.arrow.up"),
    style: .plain,
    target: self,
    action: #selector(share)
)

// After
navigationItem.rightBarButtonItem = UIBarButtonItem(
    image: UIImage(systemName: "square.and.arrow.up"),
    style: .plain,
    target: self,
    action: #selector(share)
)
navigationItem.rightBarButtonItem?.accessibilityLabel = "Share"
```

---

## Reading Order and Grouping

- In complex cells, group related content into a single VoiceOver element to reduce stops.
- Set `isAccessibilityElement = true` on the container (cell/content view) and `false` on subviews.
- Use `shouldGroupAccessibilityChildren = true` on parent views when children should be read together.
- Override `accessibilityElements` to control explicit ordering when the visual layout does not match the logical reading order.

**Example — grouping a table cell (P1):**
```swift
// Before: three separate VoiceOver stops per cell
titleLabel.text = "Invoice #0042"
subtitleLabel.text = "Due in 7 days"
amountLabel.text = "€320.00"

// After: one combined element
isAccessibilityElement = true
accessibilityTraits = [.button]
accessibilityLabel = "Invoice number 42"
accessibilityValue = "Due in 7 days. Amount €320.00"
titleLabel.isAccessibilityElement = false
subtitleLabel.isAccessibilityElement = false
amountLabel.isAccessibilityElement = false
```

---

## Custom Controls and Hit Testing

- If a `UIView` is tappable (via gesture recognizer or `touchesBegan`), it must behave as a control for accessibility: expose `.button` trait, label, and be focusable.
- Ensure touch targets are at least 44x44 pt.
- Override `point(inside:with:)` to expand the tappable area without changing the visual frame when needed.
- Use `accessibilityFrameInContainerSpace` only for custom layouts where the default frame is wrong.

---

## Dynamic Type

- Text must scale with the user's content size category preference.
- Use `UIFont.preferredFont(forTextStyle:)` for system fonts.
- For custom fonts, use `UIFontMetrics` to scale them.
- Always set `adjustsFontForContentSizeCategory = true` on labels and text views.
- Ensure Auto Layout constraints do not clip text at the largest accessibility sizes.

**Example — custom font scaling (P0):**
```swift
// Before: fixed font, does not scale
titleLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 16)

// After: scales with Dynamic Type
titleLabel.font = UIFontMetrics(forTextStyle: .headline)
    .scaledFont(for: UIFont(name: "AvenirNext-DemiBold", size: 16)
    ?? .preferredFont(forTextStyle: .headline))
titleLabel.adjustsFontForContentSizeCategory = true
```

---

## Screen Changes and Announcements

- Post `UIAccessibility.Notification.screenChanged` when a new screen appears.
- Post `.layoutChanged` when the screen content changes significantly (e.g., a section expands).
- Post `.announcement` sparingly for transient feedback (e.g., "Item added to cart").
- Always pass the element that should receive focus as the argument to `screenChanged` or `layoutChanged`.

---

## Colour, Contrast, and Non-Colour Cues

- Do not rely on colour alone for error/success/selection states.
- Add text, icons, or VoiceOver descriptions to reinforce colour-based meaning.
- Prefer system/semantic colours that adapt to light/dark mode and increased contrast settings.
- Check `UIAccessibility.isDarkerSystemColorsEnabled` if implementing custom high-contrast support.

---

## Accessibility Identifiers

- `accessibilityIdentifier` is for UI testing, not for VoiceOver.
- Do not confuse `accessibilityIdentifier` with `accessibilityLabel`.
- Only recommend identifiers when they clearly improve testability — they are out of scope for this audit.

---

## Common UIKit Mistakes (Quick Reference)

| Mistake | Severity | Fix |
|---|---|---|
| Icon-only bar button without label | P0 | Set `accessibilityLabel` |
| Custom tappable view without traits | P0 | Add `.button` trait, set label |
| Fixed font that ignores Dynamic Type | P0 | Use `UIFontMetrics` + `adjustsFontForContentSizeCategory` |
| Multiple VoiceOver stops in single cell | P1 | Group with `isAccessibilityElement` on cell |
| State not exposed (selected/disabled) | P1 | Use `accessibilityTraits` or `accessibilityValue` |
| Missing screen change announcement | P1 | Post `.screenChanged` or `.layoutChanged` |
| Colour-only state indication | P1 | Add icon, text, or VoiceOver cue |
| Small touch targets (<44pt) | P1 | Expand frame or override `point(inside:with:)` |
| `accessibilityIdentifier` used as label | P2 | Replace with `accessibilityLabel` |

---

## References

- [UIKit Accessibility](https://developer.apple.com/documentation/uikit/accessibility)
- [UIFontMetrics](https://developer.apple.com/documentation/uikit/uifontmetrics)
- [Apple HIG - Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
