---
name: ios-frameworks-swift-charts
description: Use when building or reviewing Swift Charts marks, axes, scales, legends, selection, scrolling, vectorized plots, or chart accessibility.
---

# Swift Charts

Review and write Swift Charts code for correct mark selection, axis configuration, interaction patterns, and accessibility.

## Responsibility

**Owns:** Chart and Chart3D views, all mark types (Bar/Line/Area/Point/Rule/Rectangle/Sector), vectorized plots (BarPlot/LinePlot/AreaPlot/PointPlot/RulePlot/RectanglePlot/SectorPlot), axis customization, scales, legends, selection, scrolling, annotations, ChartProxy, SurfacePlot, 3D visualization, chart accessibility.

**Does NOT own:** Data modelling or fetching (persistence/networking skills), SwiftUI view architecture beyond charts (swiftui-patterns), HealthKit or domain-specific data pipelines.

## Core Principles

1. **Choose the right mark.** Bar for comparison, Line for trends over time, Area for cumulative totals, Point for correlation, Sector for part-of-whole (max 5-7 slices), Rule for thresholds.
2. **Vectorized plots for large datasets.** Use `BarPlot`/`LinePlot` etc. instead of `ForEach` + individual marks when plotting hundreds+ of data points — single instance, better performance.
3. **Configure axes explicitly.** Auto-generated axes are a starting point. Set domain, tick values, and labels for clarity. Hide axes only when the chart is self-explanatory.
4. **Accessibility is built-in but needs help.** Swift Charts generates audio graphs automatically. Add `.accessibilityLabel` and `.accessibilityValue` to marks when the default description is insufficient.
5. **Selection needs a binding.** `chartXSelection(value:)` requires a `@State` binding. Always provide visual feedback (RuleMark, annotation) for the selected value.
6. **Scrolling needs a visible domain.** `chartScrollableAxes(.horizontal)` without `chartXVisibleDomain(length:)` shows everything — defeats the purpose.
7. **Consistent scales across related charts.** When showing multiple charts for comparison, use explicit `chartXScale(domain:)` / `chartYScale(domain:)` to align them.

## Review Process

1. Check mark type selection and configuration → `references/marks-and-plots.md`
2. Check axis, scale, legend, and interaction modifiers → `references/modifiers-and-interaction.md`
3. If using Chart3D or SurfacePlot → `references/3d-charts.md`
4. Verify accessibility (audio graph support, mark labels)
5. Check performance for large datasets (vectorized plots, visible-region filtering)

## Red Flags

| Anti-Pattern | Problem | Fix |
|---|---|---|
| ForEach + LineMark for 1000+ points | Performance overhead, one view per point | Use `LinePlot` (vectorized) |
| SectorMark with 15 categories | Unreadable pie chart | Max 5-7 sectors, group rest into "Other" |
| Missing chartXVisibleDomain with scrolling | Entire dataset visible, scrolling useless | Set `chartXVisibleDomain(length:)` |
| Selection binding without visual feedback | User taps but sees nothing | Add RuleMark + annotation for selected value |
| Hardcoded color per series | Breaks with dynamic data | Use `chartForegroundStyleScale` |
| No explicit domain on comparison charts | Auto-scaling makes charts incomparable | Set matching `chartYScale(domain:)` |

## Pre-Ship Checklist

- [ ] Correct mark type for the data relationship
- [ ] Axes configured with appropriate ticks and labels
- [ ] Legend visible and correctly mapped (or hidden if single series)
- [ ] Selection provides visual feedback (RuleMark, annotation, highlight)
- [ ] Scrolling includes visible domain constraint
- [ ] Large datasets use vectorized plots
- [ ] Foreground style scale maps data values to meaningful colours
- [ ] Accessibility: audio graph works, marks have useful labels
- [ ] Dark mode renders correctly
- [ ] Chart animates on data changes (`.animation(.default, value: data)`)

## References

- `references/marks-and-plots.md` — All mark types, vectorized plots, common modifiers
- `references/modifiers-and-interaction.md` — Axes, scales, legends, selection, scrolling, ChartProxy
- `references/3d-charts.md` — Chart3D, SurfacePlot, poses, camera projection
- `references/community-examples.md` — Visual patterns and chart styles from [Swift-Charts-Examples](https://github.com/jordibruin/Swift-Charts-Examples)
