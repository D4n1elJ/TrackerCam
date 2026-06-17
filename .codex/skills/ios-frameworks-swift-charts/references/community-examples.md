# Community Examples Reference

Source: [Swift-Charts-Examples](https://github.com/jordibruin/Swift-Charts-Examples) by Jordi Bruin et al.

Use this as inspiration when choosing chart styles or implementing specific visual patterns. Browse the repo for full source code.

## Example Catalogue

### Line Charts
| Example | Key Technique |
|---|---|
| Single Line | Basic `LineMark` with `x`/`y` |
| Lollipop | `LineMark` + `PointMark` composite |
| Animated | `.animation` on data changes |
| Gradient | `AreaMark` underneath with gradient fill |
| Multi-Line | `foregroundStyle(by:)` for series differentiation |

### Bar Charts
| Example | Key Technique |
|---|---|
| Single / Double Bar | Basic `BarMark`, grouped via `position(by:)` |
| Threshold Line | `BarMark` + `RuleMark` overlay |
| Pyramid | Mirrored horizontal bars |
| Time Sheet | Horizontal bars with date ranges |
| Sound Bar | Real-time updating bar heights |
| Horizontal Scrolling | `chartScrollableAxes(.horizontal)` + `chartXVisibleDomain` |

### Area Charts
| Example | Key Technique |
|---|---|
| Simple Area | `AreaMark` with gradient fill |
| Stacked Area | Multiple `AreaMark` with `foregroundStyle(by:)` |

### Range Charts
| Example | Key Technique |
|---|---|
| Basic Range | `RectangleMark` with y-start/y-end |
| Heart Rate | Range band with min/max values over time |
| Candlestick | `BarMark` (body) + `RuleMark` (wicks) composite |

### Heat Maps
| Example | Key Technique |
|---|---|
| Customizable Heat Map | `RectangleMark` grid with color scale |
| GitHub Contribution Graph | `RectangleMark` with discrete color buckets |

### Point Charts
| Example | Key Technique |
|---|---|
| Scatter Plot | `PointMark` with size/color encoding |
| Vector Field | `PointMark` + directional annotations |

### Apple-Style Charts
| Example | Key Technique |
|---|---|
| ECG | Dense `LineMark` with no axes |
| iPhone Storage | Stacked horizontal `BarMark` with category colors |
| Screen Time | Grouped bars with daily breakdown |

## When to Consult

- **Choosing a visual style** — browse the catalogue for inspiration before implementing
- **Composite marks** — candlestick, lollipop, and range examples show multi-mark composition
- **Real-world patterns** — Apple-style examples show production-quality chart design
- **Scrolling/animation** — working implementations of interactive chart features
