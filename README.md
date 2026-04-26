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
