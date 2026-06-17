# Foundation Models Diagnostics

Most Foundation Models problems stem from misunderstanding model capabilities (3B parameter on-device model, not world knowledge), context limits (4096 tokens), or availability requirements — not framework bugs.

## Before Modifying Code — 5 Initial Checks

1. **Availability status:** `SystemLanguageModel.default.availability` — is the model actually available?
2. **Language support:** Is the user's locale in `supportedLanguages`?
3. **Context usage:** How much of the 4096 token budget is consumed? Check `session.transcript`.
4. **Performance baseline:** Profile with Instruments (Foundation Models template) before optimising.
5. **Transcript inspection:** Read the transcript for unexpected patterns, tool call loops, or truncated output.

---

## Symptom → Diagnosis Table

| Symptom | Likely Cause | Fix | Time Est. |
|---|---|---|---|
| Feature not appearing | Availability not checked or `.unavailable` | Switch on `model.availability`, show fallback UI | 5 min |
| Crash on launch / blank AI UI | Using AI features without availability guard | Add availability check before any session creation | 5 min |
| `exceededContextWindowSize` thrown | Instructions + prompt + output exceed 4096 tokens | Break into multiple sessions, shorten instructions | 10 min |
| `guardrailViolation` thrown | Prompt triggered content policy | Rephrase prompt, check instructions aren't adversarial | 5 min |
| `unsupportedLanguageOrLocale` thrown | User locale not supported | Check `supportedLanguages`, show localised fallback | 5 min |
| Output is nonsensical / hallucinated | Asking for world knowledge or complex reasoning | Wrong tool — use server-side LLM for these tasks | 10 min |
| Wrong structure in output | Parsing strings instead of using `@Generable` | Switch to guided generation | 15 min |
| Missing fields in `@Generable` output | Missing `@Guide` descriptions or ambiguous prompt | Add descriptions to all properties, improve prompt specificity | 10 min |
| Inconsistent output across runs | Temperature too high or prompt too vague | Lower temperature, add constraints to instructions | 5 min |
| Slow first generation (1-2s delay) | Cold session start | Prewarm: create session at init, not at generation time | 5 min |
| Slow generation overall | Complex schema or large output | Simplify `@Generable` type, constrain output length | 10 min |
| UI freezes during generation | Generation on main thread without Task | Wrap in `Task {}`, use streaming for progressive display | 5 min |
| Tool called repeatedly in loop | Model can't satisfy request with tool results | Check tool output format, ensure `ToolOutput` gives the model what it needs | 15 min |

---

## Availability Failures

### Device Not Eligible

The device doesn't support Apple Intelligence. No workaround — show alternative non-AI UI.

```swift
case .unavailable(.deviceNotEligible):
    // Show manual UI path, hide AI features entirely
```

### Apple Intelligence Not Enabled

The device supports it but the user hasn't enabled it in Settings.

```swift
case .unavailable(.appleIntelligenceNotEnabled):
    // Prompt user: "Enable Apple Intelligence in Settings > Apple Intelligence & Siri"
```

### Model Not Ready

Model is downloading or updating. This is transient.

```swift
case .unavailable(.modelNotReady):
    // Show loading state, retry later
```

---

## Generation Errors

### Context Window Exceeded

The 4096 token limit is **hard**. Instructions + all prompts + all outputs in the session share this budget.

**Diagnosis:** Check transcript length. If multi-turn, the conversation history is eating the budget.

**Fixes:**
- Create a new session for independent queries (fresh budget)
- Shorten instructions (they're included in every request)
- Constrain output length ("respond in 2 sentences")
- For large data, chunk across multiple sessions and combine in Swift

### Guardrail Violation

The on-device model has content policy filters. This is not a bug.

**Fixes:**
- Rephrase the prompt to avoid triggering content filters
- Add safety instructions to guide the model away from policy-violating territory
- Catch the error and show a user-friendly "couldn't generate" message

---

## Output Quality Problems

### Hallucination / Wrong Facts

The 3B model is **not** a knowledge base. It excels at summarisation, classification, extraction, and structured generation from provided text. It does not have reliable world knowledge.

**Rule:** If the answer requires facts the user didn't provide in the prompt, use a server-side LLM or a tool that fetches real data.

### Inconsistent Structure

If string parsing produces inconsistent results, switch to `@Generable`. Guided generation constrains the model's token output to valid instances of your type — it cannot produce structurally invalid results.

### Low Quality Output

- Add `@Guide(description:)` to every property — descriptions steer the model
- Put role and constraints in `instructions`, not the prompt
- Be specific about what you want ("a 2-sentence summary focusing on key dates" not "summarise this")
- Lower temperature for more deterministic output

---

## Performance Problems

### Cold Start Latency

First generation in a session takes 1-2s longer. **Prewarm** by creating the session when the view appears, not when the user taps "Generate".

### Profiling

Use Instruments with the **Foundation Models** template to measure:
- Time to first token
- Total generation time
- Token throughput
- Context budget usage

### Schema Complexity

Deeply nested `@Generable` types with many properties increase generation time. Keep schemas focused — break large outputs across multiple sessions if needed.

---

## Testing on Real Devices

- Foundation Models requires Apple Intelligence hardware — simulator results may differ
- Test across device generations (older eligible devices will be slower)
- Test with different locales to verify language support handling
- Test with Apple Intelligence disabled to verify fallback UI
