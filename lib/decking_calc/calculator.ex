defmodule DeckingCalc.Calculator do
  @moduledoc """
  Pure calculation layer for the decking calculator.

  Computes, for a validated `DeckingCalc.Input`:

    * field-board layout (number of rows across the short axis)
    * joist count and actual centre-to-centre spacing
    * an optional picture-frame border (perimeter boards)
    * an optional transverse "breaker" frame that splits a long field run
      into shorter segments so each field row fits within stock
    * a waste-optimised cut list for field + border + band boards
    * a summary of materials purchased vs used
  """

  alias DeckingCalc.{CutList, Input}

  @type layout :: %{
          direction: Input.direction(),
          row_length: pos_integer(),
          rows_span: pos_integer(),
          row_count: pos_integer(),
          last_row_width: pos_integer(),
          field_length: pos_integer(),
          field_width: pos_integer()
        }

  @type joists :: %{
          joist_count: pos_integer(),
          actual_spacing: non_neg_integer(),
          span: pos_integer()
        }

  @type picture_frame_plan :: %{
          border_boards: pos_integer(),
          cap_length: pos_integer(),
          cap_count: pos_integer()
        }

  @type transverse_frame_plan :: %{
          band_boards: pos_integer(),
          segments: pos_integer(),
          segment_length: pos_integer(),
          band_thickness: pos_integer(),
          band_length: pos_integer(),
          band_count: non_neg_integer()
        }

  @type result :: %{
          input: Input.t(),
          layout: layout(),
          joists: joists(),
          picture_frame: picture_frame_plan() | nil,
          transverse_frame: transverse_frame_plan() | nil,
          cut_list: CutList.plan(),
          summary: %{
            total_purchased: non_neg_integer(),
            total_used: non_neg_integer(),
            total_waste: non_neg_integer(),
            waste_pct: float(),
            boards_by_stock: %{pos_integer() => non_neg_integer()},
            field_rows: pos_integer(),
            border_boards: non_neg_integer(),
            band_boards: non_neg_integer(),
            segments: pos_integer()
          }
        }

  @doc """
  Computes the full plan for the given validated input.
  """
  @spec compute(Input.t()) :: result()
  def compute(%Input{} = input) do
    layout = layout(input)
    joists = joists(input, layout)
    picture_frame = picture_frame_plan(input)
    transverse_frame = transverse_frame_plan(input, layout)

    rows = build_rows(layout, picture_frame, transverse_frame)

    cut_list =
      CutList.plan(rows,
        stock_lengths: input.stock_lengths,
        kerf: input.kerf,
        min_reuse: input.min_reuse
      )

    summary = build_summary(cut_list, layout, picture_frame, transverse_frame)

    %{
      input: input,
      layout: layout,
      joists: joists,
      picture_frame: picture_frame,
      transverse_frame: transverse_frame,
      cut_list: cut_list,
      summary: summary
    }
  end

  @doc """
  Computes the field layout: how many board rows fit across the short axis,
  what the row length is, and the resulting last-row width.
  """
  @spec layout(Input.t()) :: layout()
  def layout(%Input{} = input) do
    {long, short} = long_short(input)

    # Picture-frame end caps inset only the axis along which boards run
    # (i.e. the long axis); they do not shorten the perpendicular field
    # width because there are no long-side borders.
    border_inset =
      case input.picture_frame do
        nil -> 0
        %{border_boards: n} -> n * input.board_width + n * input.gap
      end

    field_length = max(long - 2 * border_inset, 0)
    field_width = short

    pitch = input.board_width + input.gap
    # Number of full board rows that fit in field_width, accounting for the
    # trailing gap that is *not* needed after the last board.
    row_count =
      if field_width <= 0 or pitch == 0 do
        0
      else
        div(field_width + input.gap, pitch)
      end

    used_width =
      if row_count == 0,
        do: 0,
        else: row_count * input.board_width + (row_count - 1) * input.gap

    margin = field_width - used_width

    # The last row is a full-width board unless the remaining space
    # exceeds one trailing gap; any surplus beyond that gap is absorbed by
    # ripping the final row wider to keep the field flush to the border.
    last_row_width =
      cond do
        row_count == 0 -> 0
        margin <= input.gap -> input.board_width
        true -> input.board_width + (margin - input.gap)
      end

    %{
      direction: input.board_direction,
      row_length: field_length,
      rows_span: field_width,
      row_count: row_count,
      last_row_width: last_row_width,
      field_length: field_length,
      field_width: field_width
    }
  end

  @doc """
  Computes joist count and actual spacing. Joists run perpendicular to the
  boards, spanning the short axis of the patio.
  """
  @spec joists(Input.t(), layout()) :: joists()
  def joists(%Input{} = input, layout) do
    {_long, short} = long_short(input)
    span = short
    max_spacing = input.max_joist_spacing

    joist_count =
      if span <= 0 do
        0
      else
        ceil_div(layout.field_length, max_spacing) + 1
      end

    actual_spacing =
      if joist_count > 1 do
        div(layout.field_length, joist_count - 1)
      else
        0
      end

    %{joist_count: joist_count, actual_spacing: actual_spacing, span: span}
  end

  @doc """
  Derives the cut requirements for a picture-frame border.

  The frame consists of end-cap boards laid perpendicular to the field
  boards at each end of the run. Each cap board spans the full short
  axis (perpendicular to the boards). There are no long-side borders.

  Returns `nil` when no picture frame is configured.
  """
  @spec picture_frame_plan(Input.t()) :: picture_frame_plan() | nil
  def picture_frame_plan(%Input{picture_frame: nil}), do: nil

  def picture_frame_plan(%Input{picture_frame: %{border_boards: n}} = input) do
    {_long, short} = long_short(input)

    %{
      border_boards: n,
      cap_length: short,
      cap_count: 2 * n
    }
  end

  @doc """
  Derives transverse "breaker" band geometry. Only meaningful when boards
  run along the long axis. When enabled, at least one breaker (two
  segments) is always produced; the segment count is auto-grown so that
  each segment fits within the longest available stock board.

  Returns `nil` when the transverse frame is not configured, when boards
  run :along_width, or when the field is too small to fit even one
  breaker plus two non-zero segments.
  """
  @spec transverse_frame_plan(Input.t(), layout()) :: transverse_frame_plan() | nil
  def transverse_frame_plan(%Input{transverse_frame: nil}, _layout), do: nil

  def transverse_frame_plan(%Input{board_direction: :along_width}, _layout), do: nil

  def transverse_frame_plan(
        %Input{transverse_frame: %{band_boards: bb}} = input,
        %{field_length: field_length, field_width: field_width}
      ) do
    band_thickness = bb * input.board_width + max(bb - 1, 0) * input.gap
    band_footprint = band_thickness + 2 * input.end_gap

    cond do
      field_length <= 0 ->
        nil

      # Need at least one breaker plus two non-zero segments.
      field_length <= band_footprint ->
        nil

      true ->
        max_len = input.transverse_max_segment_length || Enum.max(input.stock_lengths)
        segments = derive_segments(field_length, max_len, band_footprint, 2)
        band_count = max(segments - 1, 0)
        total_band_footprint = band_count * band_footprint
        segment_length = max(div(field_length - total_band_footprint, segments), 0)

        %{
          band_boards: bb,
          segments: segments,
          segment_length: segment_length,
          band_thickness: band_thickness,
          band_length: field_width,
          band_count: band_count
        }
    end
  end

  # Smallest n >= start such that floor((field_length - (n-1) * footprint) / n) <= max_stock.
  # Capped at 32 to guard against pathological inputs.
  defp derive_segments(_field_length, _max_stock, _footprint, n) when n >= 32, do: 32

  defp derive_segments(field_length, max_stock, footprint, n) do
    available = field_length - (n - 1) * footprint

    cond do
      available <= 0 -> max(n - 1, 1)
      div(available, n) <= max_stock -> n
      true -> derive_segments(field_length, max_stock, footprint, n + 1)
    end
  end

  @spec build_rows(layout(), picture_frame_plan() | nil, transverse_frame_plan() | nil) ::
          [{term(), pos_integer()}]
  defp build_rows(layout, picture_frame, transverse_frame) do
    field_rows(layout, transverse_frame) ++
      border_rows(picture_frame) ++
      band_rows(transverse_frame)
  end

  defp field_rows(%{row_count: 0}, _), do: []

  defp field_rows(%{row_count: rc, row_length: rl}, nil) do
    for i <- 1..rc, do: {{:field, i}, rl}
  end

  defp field_rows(%{row_count: rc}, %{segments: segs, segment_length: sl}) do
    for s <- 1..segs, i <- 1..rc, do: {{:field, s, i}, sl}
  end

  defp border_rows(nil), do: []

  defp border_rows(%{cap_count: cc, cap_length: cl}) do
    for i <- 1..cc, do: {{:border_cap, i}, cl}
  end

  defp band_rows(nil), do: []
  defp band_rows(%{band_count: 0}), do: []

  defp band_rows(%{band_count: bc, band_boards: bb, band_length: bl}) do
    for d <- 1..bc, i <- 1..bb, do: {{:band, d, i}, bl}
  end

  defp build_summary(cut_list, layout, picture_frame, transverse_frame) do
    purchased = cut_list.total_purchased
    used = cut_list.total_used
    waste = cut_list.total_waste

    waste_pct =
      if purchased > 0 do
        Float.round(waste / purchased * 100, 2)
      else
        0.0
      end

    border_count =
      case picture_frame do
        nil -> 0
        %{cap_count: cc} -> cc
      end

    {band_count, segments} =
      case transverse_frame do
        nil -> {0, 1}
        %{band_count: bc, band_boards: bb, segments: s} -> {bc * bb, s}
      end

    field_rows =
      if transverse_frame, do: layout.row_count * segments, else: layout.row_count

    %{
      total_purchased: purchased,
      total_used: used,
      total_waste: waste,
      waste_pct: waste_pct,
      boards_by_stock: cut_list.stock_usage,
      field_rows: field_rows,
      border_boards: border_count,
      band_boards: band_count,
      segments: segments
    }
  end

  # Returns `{long_axis, short_axis}` where `long_axis` is the axis
  # the boards run along. Boards running `:along_length` means their length
  # equals `patio_length`; otherwise they run along the width.
  defp long_short(%Input{
         patio_length: l,
         patio_width: w,
         board_direction: :along_length
       }),
       do: {l, w}

  defp long_short(%Input{
         patio_length: l,
         patio_width: w,
         board_direction: :along_width
       }),
       do: {w, l}

  defp ceil_div(_a, 0), do: 0
  defp ceil_div(a, b), do: div(a + b - 1, b)
end
