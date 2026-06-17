---
name: ios-frameworks-foundation-models
description: Use when implementing Apple Foundation Models sessions, guided generation, tool calling, streaming, or availability checks.
---

# Foundation Models

Review and write FoundationModels code for correct availability handling, session management, guided generation, tool calling, and streaming patterns.

## Responsibility

**Owns:** SystemLanguageModel, LanguageModelSession, @Generable, @Guide, Tool protocol, ToolOutput, GenerationOptions, snapshot streaming, context management, transcript inspection.

**Does NOT own:** Custom ML models or CoreML conversion (→ `coreml-vision` skill), Vision framework image analysis (→ `coreml-vision` skill), third-party or server-hosted LLM APIs (→ `ios-networking` skill), system-provided AI features (Writing Tools, Genmoji — no custom code needed), Siri integration (→ App Intents skill).

## Core Principles

1. **Always check availability.** `SystemLanguageModel.default.availability` must be `.available` before showing AI UI. Handle all unavailable cases gracefully.
2. **Instructions over prompts.** The model prioritizes instructions over prompts. Put role, constraints, and safety in instructions; put the specific task in the prompt.
3. **One request at a time.** A session handles one request at a time. Check `session.isResponding` before sending a new request.
4. **Use @Generable for structured output.** Don't parse strings manually — use guided generation for type-safe responses.
5. **Access response via .content.** Always use `response.content`, never `response.output`.
6. **Respect the 4096 token limit.** All instructions + prompts + outputs share a 4096 token budget per session. Break large tasks across sessions.
7. **Stream for real-time UI.** Use `streamResponse` with SwiftUI state for progressive display. Snapshots are partially generated types with optional properties.

## Review Process

1. Check availability handling → `references/foundation-models-patterns.md`
2. Check session creation and instruction quality
3. Check @Generable types for proper @Guide annotations
4. If using tools, check Tool protocol conformance and error handling
5. If streaming, check snapshot consumption pattern
6. Verify context budget is respected for the use case

## Red Flags

| Anti-Pattern | Problem | Fix |
|---|---|---|
| No availability check | Crash or blank UI on ineligible devices | Switch on `model.availability` |
| Using `response.output` | Wrong property | Use `response.content` |
| Sending while `isResponding` | Undefined behaviour | Check `isResponding` first |
| Giant prompt in single session | Exceeds 4096 token limit | Break into multiple sessions |
| Parsing strings instead of @Generable | Fragile, error-prone | Use guided generation |
| Instructions in prompt | Lower priority, less reliable | Put constraints in instructions |

## References

- `references/foundation-models-patterns.md` — Availability, sessions, generation, @Generable, tools, streaming, performance, limits
- `references/foundation-models-diagnostics.md` — Troubleshooting: availability failures, generation errors, output quality, performance
- `references/ai-design-patterns.md` — Apple HIG for presenting AI-generated content
