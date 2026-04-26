defmodule DeckingCalc.Input do
  @moduledoc """
  Validated inputs to `DeckingCalc.Calculator`.

  All linear measurements are in millimetres. The struct carries both the
  dimensional inputs (patio size, board stock, gaps, joist limits) and the
  optional picture-frame border configuration.
  """

  @type direction :: :along_length | :along_width

  @type picture_frame ::
          nil
          | %{
              border_boards: pos_integer(),
              mitre: boolean()
            }

  @type t :: %__MODULE__{
          patio_length: pos_integer(),
          patio_width: pos_integer(),
          board_width: pos_integer(),
          board_thickness: pos_integer(),
          stock_lengths: [pos_integer(), ...],
          gap: non_neg_integer(),
          end_gap: non_neg_integer(),
          board_direction: direction(),
          max_joist_spacing: pos_integer(),
          kerf: non_neg_integer(),
          min_reuse: non_neg_integer(),
          picture_frame: picture_frame()
        }

  @enforce_keys [
    :patio_length,
    :patio_width,
    :board_width,
    :stock_lengths
  ]
  defstruct patio_length: nil,
            patio_width: nil,
            board_width: nil,
            board_thickness: 25,
            stock_lengths: [3000, 3600, 6000],
            gap: 5,
            end_gap: 3,
            board_direction: :along_length,
            max_joist_spacing: 400,
            kerf: 3,
            min_reuse: 300,
            picture_frame: nil

  @fields %{
    patio_length: :pos_integer,
    patio_width: :pos_integer,
    board_width: :pos_integer,
    board_thickness: :pos_integer,
    stock_lengths: :pos_integer_list,
    gap: :non_neg_integer,
    end_gap: :non_neg_integer,
    board_direction: {:enum, [:along_length, :along_width]},
    max_joist_spacing: :pos_integer,
    kerf: :non_neg_integer,
    min_reuse: :non_neg_integer,
    picture_frame: :picture_frame
  }

  @doc """
  Builds an `Input` struct from a parameter map.

  The map keys may be atoms or strings. Returns `{:ok, input}` on success or
  `{:error, errors}` where `errors` is a map of `field => message`.
  """
  @spec new(map()) :: {:ok, t()} | {:error, %{atom() => String.t()}}
  def new(params) when is_map(params) do
    normalized = normalize_keys(params)

    {values, errors} =
      Enum.reduce(@fields, {%{}, %{}}, fn {field, type}, {vals, errs} ->
        raw = Map.get(normalized, field, default_for(field))

        case cast(type, raw) do
          {:ok, value} -> {Map.put(vals, field, value), errs}
          {:error, msg} -> {vals, Map.put(errs, field, msg)}
        end
      end)

    if map_size(errors) == 0 do
      {:ok, struct!(__MODULE__, values)}
    else
      {:error, errors}
    end
  end

  @doc """
  Convenience helper used by tests and LiveView to get the default param map
  as string keys (suitable for form rendering).
  """
  @spec default_params() :: %{String.t() => term()}
  def default_params do
    %{
      "patio_length" => 4000,
      "patio_width" => 3000,
      "board_width" => 145,
      "board_thickness" => 25,
      "stock_lengths" => "3000, 3600, 6000",
      "gap" => 5,
      "end_gap" => 3,
      "board_direction" => "along_length",
      "max_joist_spacing" => 400,
      "kerf" => 3,
      "min_reuse" => 300,
      "picture_frame_enabled" => false,
      "picture_frame_border_boards" => 1,
      "picture_frame_mitre" => true
    }
  end

  defp normalize_keys(params) do
    base =
      Enum.reduce(params, %{}, fn {k, v}, acc ->
        Map.put(acc, to_atom(k), v)
      end)

    pf =
      cond do
        Map.has_key?(base, :picture_frame) ->
          base.picture_frame

        truthy?(Map.get(base, :picture_frame_enabled)) ->
          %{
            border_boards: Map.get(base, :picture_frame_border_boards, 1),
            mitre: truthy?(Map.get(base, :picture_frame_mitre, true))
          }

        true ->
          nil
      end

    Map.put(base, :picture_frame, pf)
  end

  defp to_atom(key) when is_atom(key), do: key
  defp to_atom(key) when is_binary(key), do: String.to_existing_atom(key)

  defp default_for(:board_thickness), do: 25
  defp default_for(:stock_lengths), do: [3000, 3600, 6000]
  defp default_for(:gap), do: 5
  defp default_for(:end_gap), do: 3
  defp default_for(:board_direction), do: :along_length
  defp default_for(:max_joist_spacing), do: 400
  defp default_for(:kerf), do: 3
  defp default_for(:min_reuse), do: 300
  defp default_for(:picture_frame), do: nil
  defp default_for(_), do: nil

  defp cast(:pos_integer, v) do
    case to_integer(v) do
      {:ok, n} when n > 0 -> {:ok, n}
      {:ok, _} -> {:error, "must be greater than zero"}
      :error -> {:error, "must be a positive integer"}
    end
  end

  defp cast(:non_neg_integer, v) do
    case to_integer(v) do
      {:ok, n} when n >= 0 -> {:ok, n}
      {:ok, _} -> {:error, "must be zero or greater"}
      :error -> {:error, "must be a non-negative integer"}
    end
  end

  defp cast(:pos_integer_list, v) do
    items =
      cond do
        is_list(v) -> v
        is_binary(v) -> String.split(v, [",", " "], trim: true)
        true -> [v]
      end

    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case cast(:pos_integer, item) do
        {:ok, n} -> {:cont, {:ok, [n | acc]}}
        {:error, _} = e -> {:halt, e}
      end
    end)
    |> case do
      {:ok, []} -> {:error, "must include at least one stock length"}
      {:ok, list} -> {:ok, list |> Enum.reverse() |> Enum.uniq() |> Enum.sort(:desc)}
      {:error, _} = e -> e
    end
  end

  defp cast({:enum, allowed}, v) do
    atom =
      cond do
        is_atom(v) -> v
        is_binary(v) -> safe_to_atom(v)
        true -> nil
      end

    if atom in allowed do
      {:ok, atom}
    else
      {:error, "must be one of #{inspect(allowed)}"}
    end
  end

  defp cast(:picture_frame, nil), do: {:ok, nil}

  defp cast(:picture_frame, %{} = pf) do
    with {:ok, n} <- cast(:pos_integer, Map.get(pf, :border_boards, 1)) do
      {:ok, %{border_boards: n, mitre: truthy?(Map.get(pf, :mitre, true))}}
    end
  end

  defp cast(:picture_frame, _), do: {:error, "invalid picture frame configuration"}

  defp to_integer(v) when is_integer(v), do: {:ok, v}
  defp to_integer(v) when is_float(v), do: {:ok, trunc(v)}

  defp to_integer(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp to_integer(_), do: :error

  defp safe_to_atom(s) do
    String.to_existing_atom(s)
  rescue
    ArgumentError -> nil
  end

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("on"), do: true
  defp truthy?("1"), do: true
  defp truthy?(1), do: true
  defp truthy?(_), do: false
end
