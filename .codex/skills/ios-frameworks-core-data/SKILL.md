---
name: ios-frameworks-core-data
description: Use when writing or reviewing Core Data stacks, models, migrations, concurrency, relationships, or CloudKit integration.
---

# core-data

## Purpose

Writes, reviews, and governs Core Data persistence -- stack setup, concurrency, relationships, migrations, and CloudKit integration. Use when reading, writing, or reviewing any Core Data code or schema changes. Not for SwiftData projects (use the swiftdata skill instead).

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
- `references/concurrency-patterns.md`
- `references/migration-patterns.md`
