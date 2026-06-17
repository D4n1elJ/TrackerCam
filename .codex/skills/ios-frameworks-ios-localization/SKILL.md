---
name: ios-frameworks-ios-localization
description: Use when implementing or reviewing string catalogs, plurals, RTL, locale-aware formatting, XLIFF, or localized App Shortcuts.
---

# Localization Quick Reference

## Routing

Use for localization mechanics: string catalogs, pluralization, RTL, locale-aware formatting, XLIFF, and localized App Shortcuts. Use `ios-ux-writing` for copy quality, `app-intents` for intent or shortcut implementation, and `platform-hig` for platform wording or presentation guidance.

## Purpose

Opinionated guide for localizing iOS apps using String Catalogs, generated symbols, and locale-aware formatting. iOS 26+ only -- no `@available` checks needed.

## How to Use

1. **Pick the workflow** using the decision tree below
2. **Check anti-patterns** before shipping
3. **For String Catalog details**, read `references/string-catalogs.md`
4. **For RTL and formatting**, read `references/rtl-and-formatting.md`

## Workflow Decision Tree

```
New project, small team?                  -> String Extraction (auto)
Large app, multiple modules/packages?     -> Generated Symbols (type-safe)
Framework or Swift Package?               -> Generated Symbols + #bundle macro
Migrating legacy .strings/.stringsdict?   -> Convert to String Catalog, then pick above
```

| Workflow | How Strings Enter Catalog | Code Style | Best For |
|---|---|---|---|
| String Extraction | Xcode auto-extracts from `Text("...")` | `Text("Welcome")` | New projects, prototyping |
| Generated Symbols | Manually add via + button in catalog | `Text(.welcomeMessage)` | Large apps, multi-module |

## Core API

```swift
// SwiftUI -- auto-localized
Text("Welcome to the app!")
Label("Settings", systemImage: "gear")
Button("Save") { save() }

// Explicit localization in Swift code -- always include comment
let title = String(localized: "Settings", comment: "Tab bar title")

// Deferred localization -- pass around without resolving
let resource: LocalizedStringResource = "Recent Purchases"
Text(resource)  // Resolved at render time

// Generated symbols (Xcode 26+) -- type-safe
Text(.appHomeScreenTitle)
Text(.subtitle(friendsPosts: 42))  // With parameters
```

## Pluralization

String Catalogs handle plural forms automatically. Write the string with interpolation and Xcode creates plural variations in the catalog.

```swift
// Xcode auto-creates plural variations (one/other for English)
Text("\(count) items")
```

**Plural form counts by language**:

| Forms | Languages |
|---|---|
| 2 (one, other) | English, Spanish, French, German, Italian, Portuguese |
| 3 (one, few, many/other) | Russian, Polish, Czech, Croatian |
| 4+ | Lithuanian (3+other), Slovenian (one, two, few, other) |
| 6 (zero, one, two, few, many, other) | Arabic |

Always let the String Catalog handle plurals. Never use `"item(s)"` or conditional string building.

## Anti-Patterns

### String Construction

| Mistake | Fix |
|---|---|
| Concatenating localized fragments | Single string with interpolation |
| `"You have " + "\(count)" + " items"` | `"\(count) items"` as one localizable string |
| Hardcoded `"item(s)"` | Let String Catalog provide plural forms |
| Assuming English word order | One string per sentence, let translators reorder |

### Formatting

| Mistake | Fix |
|---|---|
| `DateFormatter.dateFormat = "MM/dd/yyyy"` | Use `.dateStyle = .short` |
| Manual currency symbol `"$\(price)"` | Use `NumberFormatter` with `.currency` style |
| `String(format: "%d items", count)` | `String(localized: "\(count) items")` |

### Missing Context

| Mistake | Fix |
|---|---|
| `String(localized: "Cancel")` without comment | Add `comment: "Button to dismiss edit sheet"` |
| No translator context for ambiguous words | Comments distinguish "Book" (noun) from "Book" (verb) |

### Layout

| Mistake | Fix |
|---|---|
| `.padding(.left, 20)` | `.padding(.leading, 20)` |
| Fixed-width text containers | Flexible layout -- German text is ~30% longer than English |
| Images that should mirror in RTL not marked | `.flipsForRightToLeftLayoutDirection(true)` |

### Architecture

| Mistake | Fix |
|---|---|
| `Text("Title")` in a Swift Package without `bundle:` | `Text("Title", bundle: #bundle)` |
| Using `.module` bundle in new code | Use `#bundle` macro (Xcode 26+) |
| Forgetting to enable "Generate String Catalog Symbols" | Enable in Build Settings for generated symbol workflow |

## Quick Checklist

- [ ] All user-facing strings localizable (no raw `let title = "Settings"` in production)
- [ ] Comments on every `String(localized:)` call
- [ ] Plurals handled via String Catalog, not string manipulation
- [ ] Leading/trailing used instead of left/right
- [ ] Dates, numbers, currencies formatted with locale-aware formatters
- [ ] Swift Packages use `bundle: #bundle` for all localized strings
- [ ] RTL layout tested with `.environment(\.layoutDirection, .rightToLeft)`
- [ ] Flexible layouts accommodate text expansion (test with German or Greek)

## Full Reference

- **String Catalogs, generated symbols, plurals, #bundle macro**: `references/string-catalogs.md`
- **RTL layout, locale formatting, text expansion**: `references/rtl-and-formatting.md`

## Global Rules

| Rule | Value |
|---|---|
| Default workflow | String Extraction for new code, Generated Symbols for multi-module |
| Always provide | `comment:` parameter on `String(localized:)` calls |
| Semantic directions | Leading/trailing, never left/right |
| Date/number formatting | Always locale-aware, never hardcoded format strings |
| Deployment target | iOS 26+ only -- no `@available` checks |
