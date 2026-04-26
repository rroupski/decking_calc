# decking_calc

Interactive calculator for laying out decking boards on a raised patio.

Given the patio dimensions, available board stock, gap/kerf tolerances and an
optional picture-frame border, the app produces:

- Field row count, row length and the width of any narrowed last row.
- Joist count and actual centre-to-centre spacing (≤ the configured maximum).
- A waste-optimised cut list per row (First-Fit-Decreasing with offcut reuse).
- Perimeter boards and cut list for the picture-frame border (mitred or butt).
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

An optional decorative border that frames the field boards around the perimeter of the patio. Enable it by checking the picture-frame option in the UI.

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `picture_frame_enabled` | boolean | no | `false` | Whether to include a picture-frame border. |
| `picture_frame_border_boards` | positive integer | no | `1` | Number of boards wide the border is on each side of the patio. |

When enabled, the calculator subtracts the border width from the available field area, generates a separate cut list for the border boards, and reports mitred or butt-jointed corner options.

### Transverse band

An optional accent band of boards running perpendicular to the main field boards (e.g. across the width of the deck).

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `transverse_frame_enabled` | boolean | no | `false` | Whether to include a transverse band. |
| `transverse_band_boards` | positive integer | no | `1` | Number of boards wide the transverse band is. |
| `transverse_max_segment_length` | positive integer | no | blank (auto) | Maximum length in mm of each field segment between breaker bands. When blank, the longest available stock board length is used as the cap. Setting a smaller value forces more breaker bands; setting a larger value may allow fewer. |

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
  patio. Joist count is `ceil(span / max_spacing) + 1`.
- Picture-frame corners are either mitred (all four sides span the outer
  edge) or butt-jointed (short sides fit between the long sides).
- Offcuts shorter than `min_reuse` are treated as waste.
- Kerf loss is applied once per actual cut (no kerf is deducted when a piece
  is used to its full length).
