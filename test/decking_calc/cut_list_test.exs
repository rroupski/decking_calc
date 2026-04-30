defmodule DeckingCalc.CutListTest do
  use ExUnit.Case, async: true

  alias DeckingCalc.CutList

  describe "plan/2" do
    test "covers rows with smallest sufficient stock" do
      plan =
        CutList.plan(
          [{{:field, 1}, 4000}, {{:field, 2}, 4000}],
          stock_lengths: [3600, 4800, 5400],
          kerf: 3,
          min_reuse: 300
        )

      # Two rows of 4000mm: smallest stock >= 4000 is 4800. Expect 2 x 4800.
      assert plan.stock_usage == %{4800 => 2}
      assert plan.total_purchased == 9600
      assert plan.total_used == 8000
      assert plan.total_waste == 1600
    end

    test "carries usable offcuts into later rows" do
      # 1 row of 5000mm + 1 row of 600mm. 5400 stock covers 5000 with a 397mm
      # offcut (after 3mm kerf); that offcut is not reusable (>=300? yes it is,
      # but 397 < 600 so it won't cover row 2). Row 2 needs 600mm -> takes
      # smallest stock >= 600, which is 3600 (only stock), producing a 2997mm
      # offcut.
      plan =
        CutList.plan(
          [{{:field, 1}, 5000}, {{:field, 2}, 600}],
          stock_lengths: [3600, 5400],
          kerf: 3,
          min_reuse: 300
        )

      assert plan.stock_usage == %{5400 => 1, 3600 => 1}
      # Row 2 offcut (2997) is saved as usable.
      assert 2997 in plan.unused_offcuts
      assert plan.total_waste == 5400 + 3600 - 5000 - 600
    end

    test "reuses a fitting offcut before buying a new board" do
      # Rows: 5000 (forces 5400 stock => 397mm offcut);
      #        3000 (3600 stock => 597mm offcut);
      #        500 (should be served by the 597 offcut rather than new stock)
      plan =
        CutList.plan(
          [{{:field, 1}, 5000}, {{:field, 2}, 3000}, {{:field, 3}, 500}],
          stock_lengths: [3600, 5400],
          kerf: 3,
          min_reuse: 300
        )

      # Only two boards bought: one 5400 and one 3600. The 500mm row comes
      # from an offcut.
      assert plan.stock_usage == %{5400 => 1, 3600 => 1}

      row_500 = Enum.find(plan.rows, &(&1.row_length == 500))
      assert [%{source: :offcut, length: 500}] = row_500.cuts
    end

    test "splits a row across multiple boards when no single stock fits" do
      # Row of 7000mm, stock options 3600/4800. Needs two boards.
      plan =
        CutList.plan([{{:field, 1}, 7000}],
          stock_lengths: [3600, 4800],
          kerf: 3,
          min_reuse: 300
        )

      row = hd(plan.rows)
      assert Enum.sum(Enum.map(row.cuts, & &1.length)) == 7000
      assert length(row.cuts) == 2
    end

    test "preserves input row order in the result" do
      rows = [{{:field, 1}, 2000}, {{:field, 2}, 4000}, {{:field, 3}, 1500}]

      plan =
        CutList.plan(rows,
          stock_lengths: [3600, 4800],
          kerf: 3,
          min_reuse: 300
        )

      ids = Enum.map(plan.rows, & &1.row_id)
      assert ids == [{:field, 1}, {:field, 2}, {:field, 3}]
    end

    test "kerf is only subtracted when an offcut is actually produced" do
      # Row exactly equal to stock length -> no offcut, no kerf lost.
      plan =
        CutList.plan([{{:field, 1}, 3600}],
          stock_lengths: [3600],
          kerf: 3,
          min_reuse: 300
        )

      assert plan.total_waste == 0
      assert plan.unused_offcuts == []
    end

    test "min_reuse: 0 terminates and produces a valid plan" do
      # Regression: with min_reuse: 0, zero-length offcuts used to be
      # reinserted into the offcut pool and then picked again for any
      # remaining length, which made fill/6 loop forever and pin a CPU.
      task =
        Task.async(fn ->
          CutList.plan(
            [{{:field, 1}, 4000}, {{:field, 2}, 2000}, {{:field, 3}, 1500}],
            stock_lengths: [3000, 4000],
            kerf: 3,
            min_reuse: 0
          )
        end)

      plan = Task.await(task, 1_000)

      assert is_map(plan)
      assert length(plan.rows) == 3
      assert plan.total_used == 4000 + 2000 + 1500
      assert Enum.all?(plan.unused_offcuts, &(&1 > 0))
    end
  end
end
