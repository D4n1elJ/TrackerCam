---
name: ios-frameworks-tipkit
description: Reviews and writes TipKit code — tip definitions, eligibility rules, events, display frequency, popover and inline tips, and testing. Use when implementing feature discovery tips.
---

# TipKit

Review and write TipKit code for correct tip definitions, eligibility rules, and display patterns.

## Responsibility

**Owns:** Tip protocol, TipView, popoverTip, tip rules (parameter-based, event-based), Tips.configure(), display frequency, tip invalidation, CloudKit sync, tip testing.

**Does NOT own:** Onboarding flows (app architecture), push notifications, UI design beyond tip display.

## Core Principles

1. **Tips are for discovery, not onboarding.** Use tips to highlight nonobvious features people haven't found. Don't use them to walk through the app.
2. **Configure at launch.** Call `Tips.configure()` in your app's init or `.task` modifier before any TipView appears.
3. **Use rules to control timing.** Parameter rules for state-based conditions, event-based rules for usage patterns.
4. **Display frequency prevents fatigue.** Set `.displayFrequency(.daily)` or `.weekly` to avoid overwhelming users.
5. **Invalidate when the feature is used.** Call `tip.invalidate(reason: .actionPerformed)` immediately when the user performs the tip's action.
6. **Test with Tips.showAllTipsForTesting().** Override eligibility rules during development.

## Red Flags

| Anti-Pattern | Problem | Fix |
|---|---|---|
| No Tips.configure() at launch | Tips never appear | Add to app init or .task |
| Tips on every screen | User fatigue, banner blindness | Max 1-2 tips visible at a time |
| No invalidation after use | Tip keeps showing after feature used | Call .invalidate(reason:) |
| Using tips for onboarding | Wrong tool for the job | Use a proper onboarding flow |
| No display frequency set | Tips appear every launch | Set .displayFrequency(.daily) |

## References

- `references/tipkit-patterns.md` — Tip protocol, TipView, popoverTip, rules, events, configuration, testing
