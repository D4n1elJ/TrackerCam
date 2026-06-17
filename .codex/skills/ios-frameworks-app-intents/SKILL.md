---
name: ios-frameworks-app-intents
description: Use when implementing or reviewing App Intents, App Shortcuts, Siri, AppEntity, EntityQuery, Spotlight, or Control Center actions.
---

# App Intents Quick Reference

## Purpose

Use when implementing, reviewing, or debugging App Intents, App Shortcuts, Siri, AppEntity, EntityQuery, parameter summaries, Spotlight intents, Focus filters, Control Center, or Action Button integrations.

## Routing

Use this skill only when the request matches the frontmatter description. If a narrower framework, platform, testing, debugging, or workflow skill clearly owns the request, use the narrower skill instead.

Before assuming project-specific setup, look for the expected docs, scripts, folders, tools, or memory files in the repository. If the required setup is missing and the workflow cannot proceed without it, ask the user for the location or permission to create it.

## Workflow

1. Read the relevant sections of `references/full-guidance.md` before acting.
2. Load any additional reference files listed below that match the task.
3. Apply the smallest workflow path that satisfies the request.
4. Verify with the appropriate build, test, lint, review, screenshot, or source check before reporting completion.

## References

- `references/full-guidance.md` - complete workflow, examples, checklists, and detailed rules moved from the original entrypoint.
- `references/intent-patterns.md`
- `references/shortcuts-automation.md`
- `references/visual-intelligence.md`
