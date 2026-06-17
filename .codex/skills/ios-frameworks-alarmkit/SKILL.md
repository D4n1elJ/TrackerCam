---
name: ios-frameworks-alarmkit
description: Use when implementing or reviewing AlarmKit alarms, countdowns, presentations, authorization, or timer flows.
---

# AlarmKit

Review and write AlarmKit code for correct authorization, alarm scheduling, presentation configuration, and Live Activities integration.

## Responsibility

**Owns:** AlarmManager, Alarm, AlarmPresentation, AlarmAttributes, AlarmMetadata, countdown timers, alarm authorization, alarm observation, Live Activities for alarm UI.

**Does NOT own:** Local notifications (UserNotifications), background task scheduling (BGTaskScheduler), timer UI design (SwiftUI skill), HealthKit or domain-specific timing.

## Core Principles

1. **Authorization first.** Always request and check authorization before scheduling. Use `authorizationState` (NOT `authorizationStatus`).
2. **Widget extension required for countdowns.** Countdown presentations need a widget extension to display in Dynamic Island and Lock Screen.
3. **Observe alarm updates.** Use `alarmUpdates` async sequence to keep app state in sync — alarms can be dismissed or modified by the system.
4. **Persist alarm IDs.** Store UUIDs you create to manage alarms later. The system does not provide a way to query "your" alarms by app context.
5. **System limits apply.** There is a cap on the number of alarms per app. Design for it.
6. **Test on device.** Alarm behaviour (notifications, Live Activities, sound) only works fully on physical devices.

## Review Process

1. Check authorization handling → `references/alarmkit-patterns.md`
2. Check alarm creation patterns (one-time, repeating, countdown)
3. Check presentation configuration (alert, countdown, paused states)
4. Check alarm management (schedule, pause, resume, cancel)
5. Check observation (alarmUpdates, authorizationUpdates)
6. If using countdowns, verify widget extension exists

## Red Flags

| Anti-Pattern | Problem | Fix |
|---|---|---|
| Using `authorizationStatus` | Wrong property name | Use `authorizationState` |
| No authorization check before scheduling | Runtime failure | Request auth first, handle denial |
| Countdown without widget extension | No Dynamic Island / Lock Screen UI | Add widget extension |
| Not observing alarmUpdates | App state goes stale | Observe async sequence |
| Not persisting alarm UUIDs | Cannot manage alarms later | Store UUIDs in app storage |

## References

- `references/alarmkit-patterns.md` — Authorization, snooze mechanism, alarm types, presentation, management, SwiftUI ViewModel, Live Activities
- **WWDC25-230** — AlarmKit introduction session
