# decking_calc

Interactive calculator for laying out decking boards on a raised patio.

Given the patio dimensions, available board stock, gap/kerf tolerances and an
optional picture-frame border, the app produces:

- Field row count, row length, and the last-row width (ripped wider than the nominal board width if needed to fill the patio flush).
- Joist count and actual centre-to-centre spacing (≤ the configured maximum).
- A waste-optimised cut list per row (First-Fit-Decreasing with offcut reuse).
- End-cap boards and cut list for the picture-frame border.
- A summary: boards to purchase by stock length, total linear metres purchased
  vs used, and waste percentage.

All measurements are in millimetres.

## Requirements

- Elixir ~> 1.19 / Erlang/OTP 28
- Phoenix 1.8 (installed via `mix archive.install hex phx_new`)

## Getting started

```bash
mix setup          # fetch deps and install assets
mix test           # run the test suite
mix phx.server     # start the app at http://localhost:4000
```

No database is required — the app is stateless and runs entirely in the
LiveView process.

## Project layout

- `lib/decking_calc/input.ex` — schemaless input validation.
- `lib/decking_calc/cut_list.ex` — FFD cut-list planner with kerf and offcut
  reuse.
- `lib/decking_calc/calculator.ex` — top-level calculator: row layout, joists,
  picture-frame geometry, and summary.
- `lib/decking_calc_web/live/calculator_live.ex` — LiveView UI.

## Input parameters

All linear measurements are in **millimetres**.

### Patio dimensions

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `patio_length` | positive integer | yes | — | Overall length of the patio (the longer axis, or whichever axis you treat as length). |
| `patio_width` | positive integer | yes | — | Overall width of the patio (the shorter axis). |

### Board stock

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `board_width` | positive integer | yes | — | Face width of each decking board (e.g. 90, 140, 150). |
| `board_thickness` | positive integer | no | `25` | Thickness of each board. Used for picture-frame geometry calculations. |
| `stock_lengths` | comma-separated list of positive integers | no | `3000, 3600, 4000` | Available lengths of purchased board stock. The cut-list planner tries each length to minimise waste. At least one length must be supplied. |

### Gaps and tolerances

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `gap` | non-negative integer | no | `5` | Side-to-side expansion gap between adjacent field boards. |
| `end_gap` | non-negative integer | no | `3` | Gap left between the end of a board and the outer frame or fascia. |
| `kerf` | non-negative integer | no | `3` | Material removed by the saw blade per cut. Applied once per actual cut; no kerf is deducted when a piece is used at its full stock length. |
| `min_reuse` | non-negative integer | no | `300` | Minimum offcut length considered worth keeping for reuse in subsequent rows. Offcuts shorter than this value are counted as waste. |

### Layout

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `board_direction` | `along_length` or `along_width` | no | `along_length` | Axis along which boards run. `along_length` means boards span the patio length and rows stack across the width; `along_width` reverses the axes. |
| `max_joist_spacing` | positive integer | no | `400` | Maximum allowable centre-to-centre spacing between joists. The calculator finds the smallest number of joists such that actual spacing ≤ this value. |

### Picture-frame border

An optional set of end-cap boards laid **perpendicular** to the field boards at each end of the run, hiding the cut ends. There are no long-side border boards.

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `picture_frame_enabled` | boolean | no | `false` | Whether to include picture-frame end caps. |
| `picture_frame_border_boards` | positive integer | no | `1` | Number of boards wide each end cap is. |

When enabled, the calculator insets the field along the axis boards run by the cap width and generates a separate cut list for the cap boards.

### Transverse band

An optional accent band of boards running perpendicular to the main field boards (e.g. across the width of the deck).

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `transverse_frame_enabled` | boolean | no | `false` | Whether to include a transverse band. |
| `transverse_band_boards` | positive integer | no | `1` | Number of boards wide the transverse band is. |
| `transverse_max_segment_length` | positive integer | no | blank (auto) | Controls the segment length between breaker bands (see modes below). When blank, the longest available stock board is used as the cap. |
| `transverse_exact_segment` | boolean | no | `false` | Switches between the two segment-length modes (see below). |

The transverse breaker frame operates in one of two modes, selected by `transverse_exact_segment`:

**Auto mode** (`transverse_exact_segment = false`, default)
Finds the minimum number of segments such that every uniformly-distributed segment is ≤ `transverse_max_segment_length` (or ≤ the longest stock board when blank). The field is then divided evenly, so all segments are the same length.

**Exact mode** (`transverse_exact_segment = true`)
Requires `transverse_max_segment_length` to be set. The first `n − 1` segments are cut to **exactly** the specified length; the last segment absorbs the remainder and may therefore be shorter. The segment count `n` is derived as:
```
n = max(floor((field_length − 1) / (d + band_footprint)) + 1, 2)
```
where `d` is the specified length and `band_footprint = band_thickness + 2 × end_gap`. If `d` is too large to fit even one breaker band between two non-trivial segments, exact mode falls back to auto mode automatically.

The *Segments* summary stat shows `n − 1 × d + last_length` when the last segment differs from the rest, and the cut list shows each row's actual length individually.

## Last-row width optimisation

When the patio dimension on the rows axis does not divide evenly into whole
board rows, the final row must be ripped to a non-standard width. The app
detects this and surfaces two affordances in the results panel:

- **Warning highlight** — the *Last-row width* stat card is highlighted in
  amber whenever the last row differs from `board_width`, making the issue
  immediately visible.
- **Warning banner** — a banner below the stats reads
  *"The final row is being ripped to X mm. Adjust the patio \<width|length\>
  to the nearest full-board fit."* and contains an **Optimize width** (or
  **Optimize length**) button.

Clicking the button recalculates the controlling patio dimension (width when
boards run along the length; length when boards run along the width) and
updates the form in place. Two candidate dimensions are evaluated:

1. **Shrink** — reduce to exactly fit the current row count with no leftover
   margin: `row_count × board_width + (row_count − 1) × gap`.
2. **Grow** — increase to fit one additional full-width row:
   `shrink_to + board_width + gap`.

The candidate closest to the original dimension is chosen, so the patio
changes by the minimum amount necessary. After the adjustment the last-row
width equals `board_width` and the banner disappears.

## Notes on assumptions

- Boards run in one direction across the entire field; the opposite axis is
  subdivided into rows of `board_width + gap`.
- Joists run perpendicular to the boards and span the short axis of the
  patio. Joist count is `ceil(field_length / max_spacing) + 1`.
- Picture-frame end caps span the full perpendicular axis at each end of
  the field; there are no long-side borders or corner joints.
- Offcuts shorter than `min_reuse` are treated as waste.
- Kerf loss is applied once per actual cut (no kerf is deducted when a piece
  is used to its full length).
