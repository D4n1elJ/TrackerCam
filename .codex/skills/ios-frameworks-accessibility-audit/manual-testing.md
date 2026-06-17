# Manual Testing Guide

This file provides concrete manual testing workflows for verifying accessibility after applying audit fixes. Each section is self-contained.

---

## VoiceOver Testing

### iOS / iPadOS

1. **Enable VoiceOver:** Settings > Accessibility > VoiceOver (or triple-click Side button if configured).
2. **Navigate the screen:** Swipe right to move through elements sequentially.
3. **Verify each element:**
   - Is the label meaningful? Would you understand it without seeing the screen?
   - Are traits correct? Buttons should announce "button", headers should announce "heading".
   - Is the reading order logical? Does it follow the visual flow?
4. **Activate controls:** Double-tap to activate buttons and links.
5. **Check for duplicates:** No element should be announced twice (parent + child).
6. **Check for missing elements:** Can you reach every interactive element by swiping?
7. **Check grouping:** Tappable rows should be a single VoiceOver stop, not multiple fragments.

### macOS

1. **Enable VoiceOver:** Cmd+F5 (or System Settings > Accessibility > VoiceOver).
2. **Navigate:** Use VO+Right Arrow (Control+Option+Right Arrow) to move through elements.
3. **Interact:** Use VO+Space to activate buttons and controls.
4. **Check key view loop:** Press Tab/Shift-Tab to cycle through interactive elements. Verify all controls are reachable and the order is predictable.
5. **Check tables/outlines:** Use arrow keys to navigate rows. Verify each row is announced with meaningful content.
6. **Verify announcements:** Trigger dynamic content changes (filtering, loading) and confirm VoiceOver announces the update.

### What to Look For

- **P0 signals:** An element says "button" with no label. A custom control is completely skipped. A screen is unreachable by keyboard.
- **P1 signals:** Reading order jumps illogically. A state change (selected, error) is not announced. Text is cut off at large sizes.
- **P2 signals:** A hint could be more descriptive. Grouping would reduce unnecessary stops.

---

## Dynamic Type Testing

### iOS / iPadOS

1. **Set large text:** Settings > Accessibility > Display & Text Size > Larger Text. Enable "Larger Accessibility Sizes" and drag to maximum.
2. **Open the screen under test.**
3. **Verify:**
   - [ ] All text is visible — nothing is truncated in a way that hides meaning.
   - [ ] Labels and values are still readable (not shrunk to illegibility by `minimumScaleFactor`).
   - [ ] Layout adapts — stacks reflow, cells grow, scroll views accommodate content.
   - [ ] Buttons and controls are still tappable (not pushed off-screen or overlapping).
4. **Also test at default size** to confirm no regressions.

**Quick alternative:** Use the Accessibility Inspector (Xcode > Open Developer Tool > Accessibility Inspector) or the Control Centre text size slider.

### macOS

1. macOS does not have iOS-style Dynamic Type, but test with:
   - Increased display zoom (System Settings > Displays > Resolution).
   - Increased sidebar/icon size if applicable.
2. Verify text is not clipped and layouts remain functional.

---

## Reduce Motion Testing

### iOS / iPadOS

1. **Enable Reduce Motion:** Settings > Accessibility > Motion > Reduce Motion.
2. **Open the screen under test.**
3. **Verify:**
   - [ ] No aggressive animations play (large-scale zooms, continuous spins, parallax effects).
   - [ ] Transitions are cross-fades or instant instead of slides/zooms.
   - [ ] Auto-playing animations are paused or replaced with a static state.
   - [ ] Interactive functionality is not affected — the screen still works.

### macOS

1. **Enable Reduce Motion:** System Settings > Accessibility > Display > Reduce motion.
2. Same verification steps as iOS.

### In Code

- SwiftUI: Check `@Environment(\.accessibilityReduceMotion)`.
- UIKit: Check `UIAccessibility.isReduceMotionEnabled`.
- AppKit: Check `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.

---

## Colour and Contrast Testing

1. **Enable Increase Contrast:**
   - iOS: Settings > Accessibility > Display & Text Size > Increase Contrast.
   - macOS: System Settings > Accessibility > Display > Increase contrast.
2. **Enable Smart/Classic Invert:** Verify the UI remains usable (images should not invert; use `accessibilityIgnoresInvertColors` on image views if needed).
3. **Check without colour:**
   - Can you distinguish all states (error, success, selected, disabled) without relying on colour?
   - Is there an icon, text label, or shape change that reinforces the colour?
4. **Use Accessibility Inspector** to check contrast ratios (minimum 4.5:1 for body text, 3:1 for large text per WCAG AA).

---

## Switch Control and Full Keyboard Access Testing

### iOS / iPadOS

1. **Enable Switch Control:** Settings > Accessibility > Switch Control (or enable Full Keyboard Access for external keyboard testing).
2. **Scan the screen:** Verify all interactive elements are highlighted in sequence.
3. **Activate elements:** Confirm actions trigger correctly.
4. **Check for unreachable elements:** Any control that cannot be reached or activated is a P0.

### macOS

1. **Enable Full Keyboard Access:** System Settings > Keyboard > Keyboard navigation (toggle on).
2. **Tab through all controls** and verify focus ring is visible and the order is correct.

---

## Post-Audit Verification Checklist Template

Copy this checklist into your audit output and fill in screen-specific steps:

```
### Manual Testing Checklist
- [ ] VoiceOver: Navigate entire screen — all elements labelled, logical order
- [ ] VoiceOver: Activate all buttons/controls — correct behaviour
- [ ] Dynamic Type: Set to largest accessibility size — no truncation of meaning
- [ ] Dynamic Type: Verify layout adapts (scrolls, reflows, no overlaps)
- [ ] Keyboard (macOS/iPad): Tab through all controls — all reachable
- [ ] Keyboard: Activate controls with Space/Enter — correct behaviour
- [ ] Colour: Distinguish all states without relying on colour
- [ ] Reduce Motion: Verify animations are suppressed or reduced
```

---

## References

- [Accessibility Inspector (Xcode)](https://developer.apple.com/documentation/accessibility/accessibility-inspector)
- [Testing Accessibility on iOS](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app)
- [Apple HIG - Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
