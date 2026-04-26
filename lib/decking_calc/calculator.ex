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
          mitre: boolean(),
          long_side_length: pos_integer(),
          short_side_length: pos_integer(),
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
            total_purchased: non_neg_integer(),
            total_used: non_neg_integer(),
            total_waste: non_neg_integer(),
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
        stock_lengths: input.stock_lengths,
        kerf: input.kerf,
        min_reuse: input.min_reuse
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
        %{border_boards: n} -> n * input.board_width + n * input.gap
      end

    field_length = max(long - 2 * border_inset, 0)
    field_width = max(short - 2 * border_inset, 0)

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
    thickness = n * input.board_width + max(n - 1, 0) * input.gap

    {long_side_len, short_side_len} =
      if mitre do
        {long, short}
      else
        {long, max(short - 2 * thickness, 0)}
      end

    %{
      border_boards: n,
      mitre: mitre,
      long_side_length: long_side_len,
      short_side_length: short_side_len,
      long_side_count: 2 * n,
      short_side_count: 2 * n
    }
  end

  @spec build_rows(layout(), picture_frame_plan() | nil) ::
          [{term(), pos_integer()}]
  defp build_rows(%{row_count: 0}, nil), do: []

  defp build_rows(%{row_count: rc, row_length: rl}, picture_frame) when rc > 0 do
    field = for i <- 1..rc, do: {{:field, i}, rl}

    border =
      case picture_frame do
        nil ->
          []

        %{
          long_side_count: lc,
          long_side_length: ll,
          short_side_count: sc,
          short_side_length: sl
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
        long_side_length: ll,
        short_side_count: sc,
        short_side_length: sl
      } ->
        long = for i <- 1..lc, do: {{:border_long, i}, ll}
        short = for i <- 1..sc, do: {{:border_short, i}, sl}
        long ++ short
    end
  end

  defp build_summary(cut_list, layout, picture_frame) do
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
        %{long_side_count: lc, short_side_count: sc} -> lc + sc
      end

    %{
      total_purchased: purchased,
      total_used: used,
      total_waste: waste,
      waste_pct: waste_pct,
      boards_by_stock: cut_list.stock_usage,
      field_rows: layout.row_count,
      border_boards: border_count
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
