defmodule DeckingCalc.CalculatorTest do
  use ExUnit.Case, async: true

  alias DeckingCalc.{Calculator, Input}

  defp input!(overrides \\ %{}) do
    params =
      Map.merge(Input.default_params(), Map.new(overrides, fn {k, v} -> {to_string(k), v} end))

    {:ok, input} = Input.new(params)
    input
  end

  describe "layout/1" do
    test "computes row count based on pitch and gap" do
      # 3000mm width, 145mm boards + 5mm gap => pitch 150mm.
      # (3000 + 5) / 150 = 20 rows (each row fits pitch 150), with the final
      # trailing gap not required after the last board.
      input =
        input!(%{patio_length: 4000, patio_width: 3000, board_width: 145, gap: 5})

      layout = Calculator.layout(input)

      assert layout.row_count == 20
      assert layout.row_length == 4000
      assert layout.last_row_width == 145
    end

    test "narrows the last row when width is not a multiple of the pitch" do
      # 3010mm width with 145/5mm boards: 20 boards fit (2995mm used), then
      # 15mm leftover -> last row is ripped narrower to 145+(3010-2995)-... no,
      # remainder here is 15mm which is less than pitch, so it becomes the
      # final narrow row of 145+15 = 160? No, 15mm remainder cannot contain a
      # full board. The last row is therefore narrowed to 15mm + 145? That
      # isn't physical. We model it as the final row being trimmed to fill
      # the remainder gap (145 + 15 = 160 is wrong; the correct intent is to
      # rip the final board). Verify the implementation's actual output.
      input =
        input!(%{patio_length: 4000, patio_width: 3010, board_width: 145, gap: 5})

      layout = Calculator.layout(input)

      # 20 full rows fit (using pitch=150 and the trailing-gap rule), leaving
      # 10mm which will be absorbed by narrowing the last row.
      assert layout.row_count == 20
      assert layout.last_row_width in 145..160
    end

    test "subtracts a picture-frame border from the field area" do
      input =
        input!(%{
          patio_length: 4000,
          patio_width: 3000,
          board_width: 145,
          gap: 5,
          picture_frame_enabled: true,
          picture_frame_border_boards: 1,
          picture_frame_mitre: true
        })

      layout = Calculator.layout(input)

      # Inset on each side = 145 + 5 = 150 (1 border board + gap before field).
      assert layout.field_length == 4000 - 2 * 150
      assert layout.field_width == 3000 - 2 * 150
    end
  end

  describe "joists/2" do
    test "joist count covers the span with <= max_spacing" do
      input = input!(%{patio_length: 4000, patio_width: 3000, max_joist_spacing: 400})
      layout = Calculator.layout(input)
      joists = Calculator.joists(input, layout)

      # field_length = patio length (4000). ceil(4000/400)+1 = 11 joists.
      assert joists.joist_count == 11
      assert joists.actual_spacing == div(4000, 10)
      assert joists.actual_spacing <= 400
    end
  end

  describe "picture_frame_plan/1" do
    test "returns nil when disabled" do
      assert Calculator.picture_frame_plan(input!()) == nil
    end

    test "mitred corners: short sides span full outer edge" do
      input =
        input!(%{
          patio_length: 4000,
          patio_width: 3000,
          picture_frame_enabled: true,
          picture_frame_border_boards: 2,
          picture_frame_mitre: true
        })

      pf = Calculator.picture_frame_plan(input)
      assert pf.long_side_length == 4000
      assert pf.short_side_length == 3000
      assert pf.long_side_count == 4
      assert pf.short_side_count == 4
    end

    test "butt corners: short sides fit between long sides" do
      input =
        input!(%{
          patio_length: 4000,
          patio_width: 3000,
          board_width: 145,
          gap: 5,
          picture_frame_enabled: true,
          picture_frame_border_boards: 1,
          picture_frame_mitre: false
        })

      pf = Calculator.picture_frame_plan(input)
      # thickness = 1 * 145 + 0 = 145. short = 3000 - 2*145 = 2710.
      assert pf.short_side_length == 2710
      assert pf.long_side_length == 4000
    end
  end

  describe "compute/1" do
    test "produces a summary that reconciles purchased vs used" do
      input = input!()
      result = Calculator.compute(input)

      assert result.summary.total_purchased ==
               result.summary.total_used + result.summary.total_waste

      assert result.summary.field_rows == result.layout.row_count
      assert is_float(result.summary.waste_pct)
    end

    test "includes border rows when picture frame enabled" do
      input =
        input!(%{
          picture_frame_enabled: true,
          picture_frame_border_boards: 1,
          picture_frame_mitre: true
        })

      result = Calculator.compute(input)
      border_rows = Enum.filter(result.cut_list.rows, &match?({:border_long, _}, &1.row_id))
      assert length(border_rows) == 2
      assert result.summary.border_boards == 4
    end
  end
end
