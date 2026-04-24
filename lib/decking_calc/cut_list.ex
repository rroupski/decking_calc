defmodule DeckingCalc.CutList do
  @moduledoc """
  Cut-list planner for decking rows.

  Given a list of row lengths (each of which must be exactly filled with one
  or more board segments) this module returns a plan describing which stock
  board each cut came from, the resulting offcut, and any usable offcut that
  can be reused on later rows.

  The algorithm is a First-Fit-Decreasing pass over the row lengths:

    * Rows are processed in descending order of length so that the hardest
      (longest) rows claim fresh stock first, leaving reusable offcuts for
      shorter rows.
    * For each row we first try to cover it with a single piece:
        1. the smallest offcut that is >= the remaining row length, or
        2. the smallest stock length that is >= the remaining row length.
      This keeps rows joint-free whenever possible.
    * Only when no single piece covers the row do we split: we use the
      largest offcut that fits, otherwise the longest available stock,
      and recurse on the leftover.
    * A saw kerf is subtracted each time a cut leaves a non-zero offcut.
    * Offcuts >= `min_reuse_mm` go back into the pool for later rows.
  """

  @type row_id :: term()
  @type cut :: %{
          source: :stock | :offcut,
          stock_length_mm: pos_integer() | nil,
          length_mm: pos_integer()
        }
  @type row_plan :: %{
          row_id: row_id(),
          row_length_mm: pos_integer(),
          cuts: [cut()]
        }
  @type plan :: %{
          rows: [row_plan()],
          stock_usage: %{pos_integer() => non_neg_integer()},
          unused_offcuts_mm: [pos_integer()],
          total_purchased_mm: non_neg_integer(),
          total_used_mm: non_neg_integer(),
          total_waste_mm: non_neg_integer()
        }

  @type opts :: [
          stock_lengths_mm: [pos_integer(), ...],
          kerf_mm: non_neg_integer(),
          min_reuse_mm: non_neg_integer()
        ]

  @doc """
  Plan cuts for a list of `{row_id, row_length_mm}` tuples.
  """
  @spec plan([{row_id(), pos_integer()}], opts()) :: plan()
  def plan(rows, opts) when is_list(rows) do
    stock = opts |> Keyword.fetch!(:stock_lengths_mm) |> Enum.sort(:desc)
    kerf = Keyword.get(opts, :kerf_mm, 3)
    min_reuse = Keyword.get(opts, :min_reuse_mm, 300)

    ordered =
      rows
      |> Enum.with_index()
      |> Enum.sort_by(fn {{_id, len}, idx} -> {-len, idx} end)

    initial = %{
      offcuts: [],
      stock_usage: %{},
      rows: %{},
      purchased_mm: 0,
      used_mm: 0
    }

    acc =
      Enum.reduce(ordered, initial, fn {{id, len}, _idx}, acc ->
        plan_row(id, len, acc, stock, kerf, min_reuse)
      end)

    rows_in_order = Enum.map(rows, fn {id, _len} -> Map.fetch!(acc.rows, id) end)

    %{
      rows: rows_in_order,
      stock_usage: acc.stock_usage,
      unused_offcuts_mm: Enum.sort(acc.offcuts, :desc),
      total_purchased_mm: acc.purchased_mm,
      total_used_mm: acc.used_mm,
      total_waste_mm: acc.purchased_mm - acc.used_mm
    }
  end

  defp plan_row(id, row_length, acc, stock, kerf, min_reuse) do
    {cuts_rev, acc} = fill(row_length, [], acc, stock, kerf, min_reuse)

    row_plan = %{
      row_id: id,
      row_length_mm: row_length,
      cuts: Enum.reverse(cuts_rev)
    }

    %{acc | rows: Map.put(acc.rows, id, row_plan)}
  end

  defp fill(0, cuts, acc, _stock, _kerf, _min_reuse), do: {cuts, acc}

  defp fill(remaining, cuts, acc, stock, kerf, min_reuse) when remaining > 0 do
    cond do
      match = pick_covering_offcut(acc.offcuts, remaining) ->
        {:ok, offcut, others} = match
        acc = %{acc | offcuts: others}
        take_from_piece(:offcut, nil, offcut, remaining, cuts, acc, stock, kerf, min_reuse)

      stock_len = covering_stock(stock, remaining) ->
        acc = buy_stock(acc, stock_len)

        take_from_piece(
          :stock,
          stock_len,
          stock_len,
          remaining,
          cuts,
          acc,
          stock,
          kerf,
          min_reuse
        )

      match = pick_largest_offcut(acc.offcuts, remaining) ->
        {:ok, offcut, others} = match
        acc = %{acc | offcuts: others}
        take_from_piece(:offcut, nil, offcut, remaining, cuts, acc, stock, kerf, min_reuse)

      true ->
        stock_len = hd(stock)
        acc = buy_stock(acc, stock_len)

        take_from_piece(
          :stock,
          stock_len,
          stock_len,
          remaining,
          cuts,
          acc,
          stock,
          kerf,
          min_reuse
        )
    end
  end

  defp buy_stock(acc, stock_len) do
    %{
      acc
      | purchased_mm: acc.purchased_mm + stock_len,
        stock_usage: Map.update(acc.stock_usage, stock_len, 1, &(&1 + 1))
    }
  end

  # Consume `cut_length` from `piece_length`, record the cut, return any
  # usable offcut to the pool, and continue filling the remaining row length.
  defp take_from_piece(
         source,
         stock_length,
         piece_length,
         remaining,
         cuts,
         acc,
         stock,
         kerf,
         min_reuse
       ) do
    cut_length = min(piece_length, remaining)

    cut = %{source: source, stock_length_mm: stock_length, length_mm: cut_length}
    cuts = [cut | cuts]
    acc = %{acc | used_mm: acc.used_mm + cut_length}

    leftover_before_kerf = piece_length - cut_length

    # A kerf is only produced when we actually cut off a piece (leftover > 0).
    leftover =
      if leftover_before_kerf > 0 do
        max(leftover_before_kerf - kerf, 0)
      else
        0
      end

    acc =
      if leftover >= min_reuse do
        %{acc | offcuts: insert_offcut(acc.offcuts, leftover)}
      else
        acc
      end

    fill(remaining - cut_length, cuts, acc, stock, kerf, min_reuse)
  end

  # Smallest offcut that is >= `remaining` (covers the row with one piece).
  defp pick_covering_offcut(offcuts, remaining) do
    case Enum.filter(offcuts, &(&1 >= remaining)) do
      [] -> nil
      fits -> {:ok, Enum.min(fits), List.delete(offcuts, Enum.min(fits))}
    end
  end

  # Longest offcut that is <= `remaining` (fits without overshooting).
  defp pick_largest_offcut(offcuts, remaining) do
    case Enum.filter(offcuts, &(&1 <= remaining)) do
      [] -> nil
      fits -> {:ok, Enum.max(fits), List.delete(offcuts, Enum.max(fits))}
    end
  end

  defp insert_offcut(offcuts, length) do
    [length | offcuts] |> Enum.sort(:desc)
  end

  # Smallest stock length >= `remaining`, or nil if none covers it.
  defp covering_stock(stock, remaining) do
    case Enum.filter(stock, &(&1 >= remaining)) do
      [] -> nil
      fits -> Enum.min(fits)
    end
  end
end
