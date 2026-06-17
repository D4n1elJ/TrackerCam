# AppKit Accessibility Audit Reference

**Platform:** macOS
**Framework:** AppKit

This file contains AppKit-specific accessibility patterns, NSAccessibility API usage, keyboard navigation rules, and fix templates. Use it when auditing macOS AppKit code.

---

## VoiceOver: Roles, Labels, Help

### Labels

- Every actionable element must expose a meaningful label via `setAccessibilityLabel(_:)`.
- Icon-only toolbar items, image buttons, and custom controls are the most common offenders.
- On macOS, `NSImage(systemSymbolName:accessibilityDescription:)` lets you set the label at image creation — use it when the image *is* the accessible element.

**Example — icon-only NSButton (P0):**
```swift
// Before
let button = NSButton(
    image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)!,
    target: self,
    action: #selector(openSettings)
)

// After
let button = NSButton(
    image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)!,
    target: self,
    action: #selector(openSettings)
)
button.setAccessibilityLabel("Settings")
```

### Help Text

- Use `setAccessibilityHelp(_:)` when the label alone does not clarify consequences (e.g., "Permanently deletes the selected items").
- Do not use help text as a substitute for a missing label.

### Roles and Role Descriptions

- Set `setAccessibilityRole(_:)` on custom views that act as buttons, checkboxes, or other controls.
- Use `setAccessibilityRoleDescription(_:)` sparingly — only when the default role description is genuinely unclear.
- Expose `accessibilityValue` for stateful controls (toggles, sliders, progress indicators).

---

## Keyboard-First Navigation and Focus

macOS users rely on keyboard navigation far more than iOS users. This is a critical audit area.

- The app must be fully usable without a mouse.
- Tab/Shift-Tab must reach all interactive elements.
- The key view loop (`nextKeyView`, `previousKeyView`) must be predictable, especially in forms and toolbars.
- Controls must be able to become first responder (`acceptsFirstResponder` returning `true`).
- Avoid "dead ends" where focus is trapped and cannot escape a region.

### Custom Controls Must Handle Keyboard

If a custom `NSView` responds to clicks, it must also respond to keyboard activation:

**Example — keyboard-operable custom control (P0):**
```swift
// Before: mouse-only
final class ClickableCardView: NSView {
    var onActivate: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }
}

// After: keyboard-operable with VoiceOver role
final class ClickableCardView: NSView {
    var onActivate: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49: // Return, Space
            onActivate?()
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "Open details" }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }
}
```

---

## Grouping and Reading Order

- Avoid too many VoiceOver stops in dense layouts.
- Group related content (title + subtitle + value) when it improves comprehension.
- Use `setAccessibilityChildren(_:)` to control the order of child elements.
- Use `setAccessibilityParent(_:)` when custom view hierarchies confuse the default tree.
- Set `setAccessibilityElement(true/false)` to include or exclude views from the accessibility tree.

---

## Tables and Outline Views

For `NSTableView` and `NSOutlineView`:

- Row content must be understandable when read by VoiceOver.
- Selection state must be discoverable (`accessibilitySelected`).
- Column headers should be accessible when visible.
- Custom cell views must expose meaningful labels and values — do not rely on the raw view hierarchy.

**Example — table row summary (P1):**
```swift
// Set on the custom cell view
setAccessibilityLabel("Invoice number 42")
setAccessibilityValue("Due in 7 days. Amount €320.00")
```

---

## Text and Font Scaling

macOS does not have the same Dynamic Type system as iOS, but you should still:

- Avoid hard-coded tiny fonts (e.g., `NSFont.systemFont(ofSize: 9)`) that become illegible.
- Prefer `NSFont.preferredFont(forTextStyle:)` (macOS 11+) where available.
- Use system fonts that respect the user's display scaling preferences.
- Ensure Auto Layout does not clip text when users increase display zoom or font size.

---

## Announcements for Content Changes

When content updates without a focus change (loading results, filtering, form validation):

- Use `NSAccessibility.post(element:notification:)` with the appropriate notification.
- Use `.layoutChanged` when the screen structure changes.
- Avoid excessive announcements — only announce changes that the user needs to know about.

---

## Colour, Contrast, and Non-Colour Cues

- Do not rely on colour alone for status (error, success, selection).
- Provide icons, text labels, or VoiceOver cues to reinforce colour-based state.
- Prefer system colours that adapt to Increased Contrast and light/dark appearance.
- Check `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` for custom high-contrast support.

---

## Common AppKit Mistakes (Quick Reference)

| Mistake | Severity | Fix |
|---|---|---|
| Icon-only button without label | P0 | `setAccessibilityLabel("...")` |
| Custom view only responds to mouse | P0 | Add `acceptsFirstResponder`, `keyDown`, role |
| No key view loop in form | P0 | Set `nextKeyView` / `previousKeyView` chain |
| Table row not summarised for VoiceOver | P1 | Set label/value on cell view |
| Selection state not exposed | P1 | Use `accessibilitySelected` |
| Missing announcement on content update | P1 | Post accessibility notification |
| Hard-coded tiny font | P1 | Use system font or preferred text style |
| Colour-only state indication | P1 | Add icon, text, or VoiceOver cue |
| Overuse of `accessibilityRoleDescription` | P2 | Remove unless default role description is wrong |

---

## References

- [AppKit Accessibility](https://developer.apple.com/documentation/appkit/accessibility)
- [NSResponder (Keyboard Navigation)](https://developer.apple.com/documentation/appkit/nsresponder)
- [Apple HIG - Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
