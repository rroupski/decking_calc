defmodule DeckingCalc.Calculator do
  @moduledoc """
  Pure calculation layer for the decking calculator.

  Computes, for a validated `DeckingCalc.Input`:

    * field-board layout (number of rows across the short axis)
    * joist count and actual centre-to-centre spacing
    * an optional picture-frame border (perimeter boards)
    * a waste-optimised cut list for field + border boards
    * a summary of materials purchased vs used
  """

  alias DeckingCalc.{CutList, Input}

  @type layout :: %{
          direction: Input.direction(),
          row_length_mm: pos_integer(),
          rows_span_mm: pos_integer(),
          row_count: pos_integer(),
          last_row_width_mm: pos_integer(),
          field_length_mm: pos_integer(),
          field_width_mm: pos_integer()
        }

  @type joists :: %{
          joist_count: pos_integer(),
          actual_spacing_mm: non_neg_integer(),
          span_mm: pos_integer()
        }

  @type picture_frame_plan :: %{
          border_boards: pos_integer(),
          mitre: boolean(),
          long_side_length_mm: pos_integer(),
          short_side_length_mm: pos_integer(),
          long_side_count: pos_integer(),
          short_side_count: pos_integer()
        }

  @type result :: %{
          input: Input.t(),
          layout: layout(),
          joists: joists(),
          picture_frame: picture_frame_plan() | nil,
          cut_list: CutList.plan(),
          summary: %{
            total_purchased_mm: non_neg_integer(),
            total_used_mm: non_neg_integer(),
            total_waste_mm: non_neg_integer(),
            waste_pct: float(),
            boards_by_stock: %{pos_integer() => non_neg_integer()},
            field_rows: pos_integer(),
            border_boards: non_neg_integer()
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

    rows = build_rows(layout, picture_frame)

    cut_list =
      CutList.plan(rows,
        stock_lengths_mm: input.stock_lengths_mm,
        kerf_mm: input.kerf_mm,
        min_reuse_mm: input.min_reuse_mm
      )

    summary = build_summary(cut_list, layout, picture_frame)

    %{
      input: input,
      layout: layout,
      joists: joists,
      picture_frame: picture_frame,
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

    border_inset =
      case input.picture_frame do
        nil -> 0
        %{border_boards: n} -> n * input.board_width_mm + n * input.gap_mm
      end

    field_length_mm = max(long - 2 * border_inset, 0)
    field_width_mm = max(short - 2 * border_inset, 0)

    pitch = input.board_width_mm + input.gap_mm
    # Number of full board rows that fit in field_width_mm, accounting for the
    # trailing gap that is *not* needed after the last board.
    row_count =
      if field_width_mm <= 0 or pitch == 0 do
        0
      else
        div(field_width_mm + input.gap_mm, pitch)
      end

    used_width =
      if row_count == 0,
        do: 0,
        else: row_count * input.board_width_mm + (row_count - 1) * input.gap_mm

    margin = field_width_mm - used_width

    # The last row is a full-width board unless the remaining space
    # exceeds one trailing gap; any surplus beyond that gap is absorbed by
    # ripping the final row wider to keep the field flush to the border.
    last_row_width_mm =
      cond do
        row_count == 0 -> 0
        margin <= input.gap_mm -> input.board_width_mm
        true -> input.board_width_mm + (margin - input.gap_mm)
      end

    %{
      direction: input.board_direction,
      row_length_mm: field_length_mm,
      rows_span_mm: field_width_mm,
      row_count: row_count,
      last_row_width_mm: last_row_width_mm,
      field_length_mm: field_length_mm,
      field_width_mm: field_width_mm
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
    max_spacing = input.max_joist_spacing_mm

    joist_count =
      if span <= 0 do
        0
      else
        ceil_div(layout.field_length_mm, max_spacing) + 1
      end

    actual_spacing =
      if joist_count > 1 do
        div(layout.field_length_mm, joist_count - 1)
      else
        0
      end

    %{joist_count: joist_count, actual_spacing_mm: actual_spacing, span_mm: span}
  end

  @doc """
  Derives the perimeter cut requirements for a picture-frame border.
  Returns `nil` when no picture frame is configured.
  """
  @spec picture_frame_plan(Input.t()) :: picture_frame_plan() | nil
  def picture_frame_plan(%Input{picture_frame: nil}), do: nil

  def picture_frame_plan(%Input{picture_frame: %{border_boards: n, mitre: mitre}} = input) do
    {long, short} = long_short(input)
    # For a mitre joint the corner boards span the full outer edge; for butt
    # joints the short sides fit between the long sides, so subtract twice
    # the border thickness (border_boards * board_width + gaps).
    thickness = n * input.board_width_mm + max(n - 1, 0) * input.gap_mm

    {long_side_len, short_side_len} =
      if mitre do
        {long, short}
      else
        {long, max(short - 2 * thickness, 0)}
      end

    %{
      border_boards: n,
      mitre: mitre,
      long_side_length_mm: long_side_len,
      short_side_length_mm: short_side_len,
      long_side_count: 2 * n,
      short_side_count: 2 * n
    }
  end

  @spec build_rows(layout(), picture_frame_plan() | nil) ::
          [{term(), pos_integer()}]
  defp build_rows(%{row_count: 0}, nil), do: []

  defp build_rows(%{row_count: rc, row_length_mm: rl}, picture_frame) when rc > 0 do
    field = for i <- 1..rc, do: {{:field, i}, rl}

    border =
      case picture_frame do
        nil ->
          []

        %{
          long_side_count: lc,
          long_side_length_mm: ll,
          short_side_count: sc,
          short_side_length_mm: sl
        } ->
          long = for i <- 1..lc, do: {{:border_long, i}, ll}
          short = for i <- 1..sc, do: {{:border_short, i}, sl}
          long ++ short
      end

    field ++ border
  end

  defp build_rows(_layout, picture_frame) do
    case picture_frame do
      nil ->
        []

      %{
        long_side_count: lc,
        long_side_length_mm: ll,
        short_side_count: sc,
        short_side_length_mm: sl
      } ->
        long = for i <- 1..lc, do: {{:border_long, i}, ll}
        short = for i <- 1..sc, do: {{:border_short, i}, sl}
        long ++ short
    end
  end

  defp build_summary(cut_list, layout, picture_frame) do
    purchased = cut_list.total_purchased_mm
    used = cut_list.total_used_mm
    waste = cut_list.total_waste_mm

    waste_pct =
      if purchased > 0 do
        Float.round(waste / purchased * 100, 2)
      else
        0.0
      end

    border_count =
      case picture_frame do
        nil -> 0
        %{long_side_count: lc, short_side_count: sc} -> lc + sc
      end

    %{
      total_purchased_mm: purchased,
      total_used_mm: used,
      total_waste_mm: waste,
      waste_pct: waste_pct,
      boards_by_stock: cut_list.stock_usage,
      field_rows: layout.row_count,
      border_boards: border_count
    }
  end

  # Returns `{long_axis_mm, short_axis_mm}` where `long_axis_mm` is the axis
  # the boards run along. Boards running `:along_length` means their length
  # equals `patio_length_mm`; otherwise they run along the width.
  defp long_short(%Input{
         patio_length_mm: l,
         patio_width_mm: w,
         board_direction: :along_length
       }),
       do: {l, w}

  defp long_short(%Input{
         patio_length_mm: l,
         patio_width_mm: w,
         board_direction: :along_width
       }),
       do: {w, l}

  defp ceil_div(_a, 0), do: 0
  defp ceil_div(a, b), do: div(a + b - 1, b)
end
