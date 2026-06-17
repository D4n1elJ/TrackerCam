---
name: ios-frameworks-activitykit
description: Use when implementing or reviewing Live Activities, Dynamic Island, Lock Screen presentations, or ActivityKit updates.
---

# ActivityKit / Live Activities

Review and write ActivityKit code for correct activity lifecycle, push updates, and presentation layouts.

## Responsibility

**Owns:** Activity class, ActivityAttributes, ActivityContent, start/update/end lifecycle, ActivityKit push notifications, push token management, Dynamic Island layouts (compact/expanded/minimal), Lock Screen presentation, stale dates, alert configurations.

**Does NOT own:** Widget timeline mechanisms (WidgetKit), UI design (SwiftUI skill), push notification infrastructure (server-side), AlarmKit integration.

## Core Principles

1. **Activities are temporary.** Max 8 hours (12 with stale date). Not for persistent content.
2. **Updates come from app or push.** Use ActivityKit in-app for local updates, push notifications for server-driven updates.
3. **Widget extension renders the UI.** Live Activities share the widget extension target.
4. **Dynamic Island has 4 presentations.** Compact leading, compact trailing, expanded, minimal. Design for all.
5. **Push tokens change.** Observe token updates and send new tokens to your server.
6. **End activities explicitly.** Don't rely on timeout — end when the activity completes.
7. **Content state must be small.** Encode to < 4KB for push updates.
8. **NSSupportsLiveActivities required.** Set to true in Info.plist.

## Red Flags

| Anti-Pattern | Problem | Fix |
|---|---|---|
| No NSSupportsLiveActivities | Activities fail silently | Add to Info.plist |
| Content state > 4KB | Push updates rejected | Keep state minimal |
| Not observing push token changes | Server has stale token | Observe Activity.pushTokenUpdates |
| Not ending completed activities | Stale content on Lock Screen | Call activity.end() |
| Complex layouts in minimal presentation | Truncated/unreadable | Keep minimal to icon + small text |

## References

- `references/activitykit-patterns.md` — Attributes, lifecycle, push tokens, Dynamic Island layouts, constraints
