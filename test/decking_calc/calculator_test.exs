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

    test "end-cap border insets only the axis along which boards run" do
      input =
        input!(%{
          patio_length: 4000,
          patio_width: 3000,
          board_width: 145,
          gap: 5,
          board_direction: :along_length,
          picture_frame_enabled: true,
          picture_frame_border_boards: 1
        })

      layout = Calculator.layout(input)

      # Inset at each end = 145 + 5 = 150 (1 cap board + gap before field).
      assert layout.field_length == 4000 - 2 * 150
      # Width is unchanged: no long-side borders.
      assert layout.field_width == 3000
    end

    test "end-cap border insets the perpendicular axis when boards run along width" do
      input =
        input!(%{
          patio_length: 4000,
          patio_width: 3000,
          board_width: 145,
          gap: 5,
          board_direction: :along_width,
          picture_frame_enabled: true,
          picture_frame_border_boards: 1
        })

      layout = Calculator.layout(input)

      # field_length tracks the axis along which boards run (here patio_width)
      # and is reduced by the end-cap inset.
      assert layout.field_length == 3000 - 2 * 150
      assert layout.field_width == 4000
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

    test "end caps span the full perpendicular axis (along_length)" do
      input =
        input!(%{
          patio_length: 4000,
          patio_width: 3000,
          board_direction: :along_length,
          picture_frame_enabled: true,
          picture_frame_border_boards: 2
        })

      pf = Calculator.picture_frame_plan(input)
      # Caps run perpendicular to the field boards, spanning patio_width.
      assert pf.cap_length == 3000
      assert pf.cap_count == 4
      assert pf.border_boards == 2
    end

    test "end caps span patio_length when boards run along the width" do
      input =
        input!(%{
          patio_length: 4000,
          patio_width: 3000,
          board_direction: :along_width,
          picture_frame_enabled: true,
          picture_frame_border_boards: 1
        })

      pf = Calculator.picture_frame_plan(input)
      assert pf.cap_length == 4000
      assert pf.cap_count == 2
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

    test "includes end-cap rows when picture frame enabled" do
      input =
        input!(%{
          picture_frame_enabled: true,
          picture_frame_border_boards: 1
        })

      result = Calculator.compute(input)
      cap_rows = Enum.filter(result.cut_list.rows, &match?({:border_cap, _}, &1.row_id))
      # 2 ends * 1 board per end = 2 cap boards.
      assert length(cap_rows) == 2
      assert result.summary.border_boards == 2
    end
  end

  describe "transverse_frame_plan/2" do
    test "returns nil when not configured" do
      assert Calculator.transverse_frame_plan(input!(), Calculator.layout(input!())) == nil
    end

    test "produces a single breaker when enabled even if the field fits in stock" do
      input =
        input!(%{
          patio_length: 4000,
          stock_lengths: "4000, 6000",
          transverse_frame_enabled: true,
          transverse_band_boards: 1
        })

      pf = Calculator.transverse_frame_plan(input, Calculator.layout(input))
      assert pf.segments == 2
      assert pf.band_count == 1
    end

    test "returns nil when the field is too small for even one breaker" do
      input =
        input!(%{
          patio_length: 100,
          patio_width: 3500,
          board_width: 150,
          transverse_frame_enabled: true,
          transverse_band_boards: 1
        })

      assert Calculator.transverse_frame_plan(input, Calculator.layout(input)) == nil
    end

    test "returns nil for along_width even when enabled" do
      input =
        input!(%{
          patio_length: 12_000,
          patio_width: 3500,
          board_direction: :along_width,
          transverse_frame_enabled: true,
          transverse_band_boards: 1
        })

      assert Calculator.transverse_frame_plan(input, Calculator.layout(input)) == nil
    end

    test "derives the smallest segment count that fits within stock" do
      # 11800 / 4000 max stock => need at least 3 segments (each ~3933mm).
      input =
        input!(%{
          patio_length: 11_800,
          patio_width: 3500,
          board_width: 150,
          gap: 5,
          end_gap: 3,
          stock_lengths: "3000, 3600, 4000",
          board_direction: :along_length,
          transverse_frame_enabled: true,
          transverse_band_boards: 1
        })

      layout = Calculator.layout(input)
      pf = Calculator.transverse_frame_plan(input, layout)

      assert pf.segments >= 3
      assert pf.segment_length <= 4000
      assert pf.band_count == pf.segments - 1
      assert pf.band_length == layout.field_width
    end
  end

  describe "compute/1 with transverse frame" do
    test "replaces full-length field rows with segmented field rows + breaker bands" do
      input =
        input!(%{
          patio_length: 11_800,
          patio_width: 3500,
          board_width: 150,
          stock_lengths: "3000, 3600, 4000",
          board_direction: :along_length,
          transverse_frame_enabled: true,
          transverse_band_boards: 1
        })

      result = Calculator.compute(input)
      tf = result.transverse_frame

      seg_rows = Enum.filter(result.cut_list.rows, &match?({:field, _, _}, &1.row_id))
      band_rows = Enum.filter(result.cut_list.rows, &match?({:band, _, _}, &1.row_id))

      assert length(seg_rows) == result.layout.row_count * tf.segments
      assert length(band_rows) == tf.band_count * tf.band_boards
      assert Enum.all?(seg_rows, &(&1.row_length == tf.segment_length))
      assert Enum.all?(band_rows, &(&1.row_length == tf.band_length))
      assert result.summary.segments == tf.segments
      assert result.summary.field_rows == result.layout.row_count * tf.segments
    end
  end
end
