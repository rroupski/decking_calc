defmodule DeckingCalc.InputTest do
  use ExUnit.Case, async: true

  alias DeckingCalc.Input

  test "builds from default params" do
    assert {:ok, input} = Input.new(Input.default_params())
    assert input.patio_length == 4000
    assert input.stock_lengths == [4000, 3600, 3000]
    assert input.picture_frame == nil
  end

  test "enables picture frame when checkbox is on" do
    params =
      Input.default_params()
      |> Map.put("picture_frame_enabled", "true")
      |> Map.put("picture_frame_border_boards", "2")

    assert {:ok, input} = Input.new(params)
    assert input.picture_frame == %{border_boards: 2}
  end

  test "reports per-field errors" do
    params = Map.put(Input.default_params(), "patio_length", "not-a-number")
    assert {:error, errors} = Input.new(params)
    assert errors[:patio_length]
  end

  test "parses stock lengths from comma-separated string" do
    params = Map.put(Input.default_params(), "stock_lengths", "3600, 4800")
    assert {:ok, input} = Input.new(params)
    assert input.stock_lengths == [4800, 3600]
  end

  describe "transverse_max_segment_length" do
    test "is nil by default" do
      assert {:ok, input} = Input.new(Input.default_params())
      assert input.transverse_max_segment_length == nil
    end

    test "parses a positive integer" do
      params = Map.put(Input.default_params(), "transverse_max_segment_length", "3000")
      assert {:ok, input} = Input.new(params)
      assert input.transverse_max_segment_length == 3000
    end

    test "treats blank string as nil" do
      params = Map.put(Input.default_params(), "transverse_max_segment_length", "")
      assert {:ok, input} = Input.new(params)
      assert input.transverse_max_segment_length == nil
    end

    test "rejects zero" do
      params = Map.put(Input.default_params(), "transverse_max_segment_length", "0")
      assert {:error, errors} = Input.new(params)
      assert errors[:transverse_max_segment_length]
    end

    test "rejects non-numeric input" do
      params = Map.put(Input.default_params(), "transverse_max_segment_length", "lots")
      assert {:error, errors} = Input.new(params)
      assert errors[:transverse_max_segment_length]
    end
  end

  test "ignores Phoenix bookkeeping keys (_unused_*, _target, _csrf_token)" do
    params =
      Input.default_params()
      |> Map.put("_unused_board_direction", "")
      |> Map.put("_unused_picture_frame_mitre", "")
      |> Map.put("_target", ["calc", "patio_length"])
      |> Map.put("_csrf_token", "abc123")
      |> Map.put("unknown_field", "ignored")

    assert {:ok, input} = Input.new(params)
    assert input.patio_length == 4000
  end
end
