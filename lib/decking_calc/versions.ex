defmodule DeckingCalc.Versions do
  @moduledoc """
  Persistence for named decking-calculator input versions.

  A "version" is a string-keyed params map (the same shape produced by
  `DeckingCalc.Input.default_params/0` and the calculator form) stored under
  a user-supplied name. The whole catalogue lives as a single JSON document on
  disk; reads tolerate a missing or corrupt file by returning an empty list.

  Writes go through a temp file + rename so partial writes can never corrupt
  the catalogue.

  The on-disk path is resolved via `path/0`:

    * `Application.get_env(:decking_calc, :versions_path)` if set, else
    * `<priv>/saved_versions.json`.
  """

  @max_name_length 60

  @type version :: %{name: String.t(), updated_at: DateTime.t(), params: map()}
  @type version_summary :: %{name: String.t(), updated_at: DateTime.t()}

  @doc "Returns all saved versions, sorted by `updated_at` descending (most recent first)."
  @spec list() :: [version_summary()]
  def list do
    read_all()
    |> Enum.map(fn v -> %{name: v.name, updated_at: v.updated_at} end)
    |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
  end

  @doc "Returns the saved params map for the given name."
  @spec get(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get(name) when is_binary(name) do
    case find_by_name(read_all(), name) do
      nil -> {:error, :not_found}
      version -> {:ok, version.params}
    end
  end

  @doc """
  Creates or overwrites a version under the given name.

  Returns the saved version on success. Returns `{:error, :invalid_name}` if
  the trimmed name is empty or longer than #{@max_name_length} characters,
  and `{:error, :invalid_params}` if `params` isn't a map.
  """
  @spec save(String.t(), map()) :: {:ok, version()} | {:error, :invalid_name | :invalid_params}
  def save(name, params) when is_binary(name) and is_map(params) do
    with {:ok, clean_name} <- validate_name(name) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      new_version = %{name: clean_name, updated_at: now, params: stringify_keys(params)}

      versions =
        read_all()
        |> Enum.reject(&(&1.name == clean_name))
        |> List.insert_at(0, new_version)

      :ok = write_all(versions)
      {:ok, new_version}
    end
  end

  def save(_name, _params), do: {:error, :invalid_params}

  @doc "Deletes the named version. Returns `{:error, :not_found}` if it does not exist."
  @spec delete(String.t()) :: :ok | {:error, :not_found}
  def delete(name) when is_binary(name) do
    versions = read_all()

    case find_by_name(versions, name) do
      nil ->
        {:error, :not_found}

      _ ->
        :ok = write_all(Enum.reject(versions, &(&1.name == name)))
    end
  end

  @doc """
  Renames an existing version. Returns `{:error, :not_found}` if `old` doesn't
  exist, `{:error, :name_taken}` if a different version already uses `new`,
  and `{:error, :invalid_name}` if the new name is invalid.
  """
  @spec rename(String.t(), String.t()) ::
          :ok | {:error, :not_found | :name_taken | :invalid_name}
  def rename(old, new) when is_binary(old) and is_binary(new) do
    versions = read_all()

    with {:ok, clean_new} <- validate_name(new),
         {:found, %{} = version} <- {:found, find_by_name(versions, old)},
         :ok <- ensure_name_available(versions, clean_new, old) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      updated = %{version | name: clean_new, updated_at: now}

      versions
      |> Enum.reject(&(&1.name == old))
      |> List.insert_at(0, updated)
      |> write_all()
    else
      {:found, nil} -> {:error, :not_found}
      {:error, _} = err -> err
    end
  end

  @doc """
  Merges a stored params map onto the calculator's default params so any keys
  that were added since the version was saved get sensible defaults.
  """
  @spec merge_with_defaults(map()) :: map()
  def merge_with_defaults(params) when is_map(params) do
    Map.merge(DeckingCalc.Input.default_params(), stringify_keys(params))
  end

  @doc "Returns the resolved on-disk path of the versions catalogue."
  @spec path() :: Path.t()
  def path do
    case Application.get_env(:decking_calc, :versions_path) do
      nil -> Path.join(Application.app_dir(:decking_calc, "priv"), "saved_versions.json")
      configured -> configured
    end
  end

  ## Internals

  defp read_all do
    case File.read(path()) do
      {:ok, contents} -> decode(contents)
      {:error, _} -> []
    end
  end

  defp decode(contents) do
    case Jason.decode(contents) do
      {:ok, %{"versions" => versions}} when is_list(versions) ->
        versions
        |> Enum.map(&decode_version/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp decode_version(%{"name" => name, "updated_at" => updated_at, "params" => params})
       when is_binary(name) and is_binary(updated_at) and is_map(params) do
    case DateTime.from_iso8601(updated_at) do
      {:ok, dt, _offset} -> %{name: name, updated_at: dt, params: params}
      _ -> nil
    end
  end

  defp decode_version(_), do: nil

  defp write_all(versions) do
    payload = %{
      "versions" =>
        Enum.map(versions, fn v ->
          %{
            "name" => v.name,
            "updated_at" => DateTime.to_iso8601(v.updated_at),
            "params" => v.params
          }
        end)
    }

    target = path()
    File.mkdir_p!(Path.dirname(target))

    tmp = target <> ".tmp"
    File.write!(tmp, Jason.encode!(payload))
    File.rename!(tmp, target)
    :ok
  end

  defp find_by_name(versions, name), do: Enum.find(versions, &(&1.name == name))

  defp validate_name(name) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" -> {:error, :invalid_name}
      String.length(trimmed) > @max_name_length -> {:error, :invalid_name}
      true -> {:ok, trimmed}
    end
  end

  defp ensure_name_available(versions, new_name, old_name) do
    case find_by_name(versions, new_name) do
      nil -> :ok
      %{name: ^old_name} -> :ok
      _ -> {:error, :name_taken}
    end
  end

  defp stringify_keys(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
