defmodule DeckingCalc.VersionsTest do
  use ExUnit.Case, async: false

  alias DeckingCalc.Versions

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "decking_calc_versions_#{System.unique_integer([:positive])}.json"
      )

    prior = Application.get_env(:decking_calc, :versions_path)
    Application.put_env(:decking_calc, :versions_path, path)

    on_exit(fn ->
      File.rm(path)
      File.rm(path <> ".tmp")

      case prior do
        nil -> Application.delete_env(:decking_calc, :versions_path)
        value -> Application.put_env(:decking_calc, :versions_path, value)
      end
    end)

    {:ok, path: path}
  end

  describe "list/0" do
    test "returns an empty list when no file exists" do
      assert Versions.list() == []
    end

    test "returns versions sorted by updated_at descending" do
      {:ok, _} = Versions.save("first", %{"patio_length" => 1000})
      Process.sleep(1100)
      {:ok, _} = Versions.save("second", %{"patio_length" => 2000})

      assert [%{name: "second"}, %{name: "first"}] = Versions.list()
    end
  end

  describe "save/2" do
    test "creates and retrieves a version" do
      assert {:ok, %{name: "Front patio"}} =
               Versions.save("Front patio", %{"patio_length" => 4500})

      assert {:ok, %{"patio_length" => 4500}} = Versions.get("Front patio")
    end

    test "trims whitespace in names" do
      assert {:ok, %{name: "Trimmed"}} = Versions.save("  Trimmed  ", %{"patio_length" => 1})
      assert {:ok, _} = Versions.get("Trimmed")
    end

    test "overwrites a version with the same name" do
      {:ok, _} = Versions.save("dup", %{"patio_length" => 1000})
      {:ok, _} = Versions.save("dup", %{"patio_length" => 9999})

      assert [%{name: "dup"}] = Versions.list()
      assert {:ok, %{"patio_length" => 9999}} = Versions.get("dup")
    end

    test "rejects empty or whitespace-only names" do
      assert {:error, :invalid_name} = Versions.save("", %{})
      assert {:error, :invalid_name} = Versions.save("   ", %{})
    end

    test "rejects names longer than 60 characters" do
      assert {:error, :invalid_name} = Versions.save(String.duplicate("a", 61), %{})
    end

    test "rejects non-map params" do
      assert {:error, :invalid_params} = Versions.save("x", "not a map")
    end

    test "stringifies atom keys" do
      {:ok, _} = Versions.save("atomic", %{patio_length: 3000, board_width: 150})

      assert {:ok, %{"patio_length" => 3000, "board_width" => 150}} = Versions.get("atomic")
    end
  end

  describe "get/1" do
    test "returns :not_found for missing names" do
      assert {:error, :not_found} = Versions.get("nope")
    end
  end

  describe "delete/1" do
    test "removes a version" do
      {:ok, _} = Versions.save("temp", %{})
      assert :ok = Versions.delete("temp")
      assert {:error, :not_found} = Versions.get("temp")
    end

    test "returns :not_found when version does not exist" do
      assert {:error, :not_found} = Versions.delete("missing")
    end
  end

  describe "rename/2" do
    test "renames an existing version" do
      {:ok, _} = Versions.save("old", %{"patio_length" => 1000})
      assert :ok = Versions.rename("old", "new")
      assert {:error, :not_found} = Versions.get("old")
      assert {:ok, %{"patio_length" => 1000}} = Versions.get("new")
    end

    test "rejects renaming to an existing distinct name" do
      {:ok, _} = Versions.save("a", %{})
      {:ok, _} = Versions.save("b", %{})
      assert {:error, :name_taken} = Versions.rename("a", "b")
    end

    test "renaming to the same name is a no-op success" do
      {:ok, _} = Versions.save("same", %{})
      assert :ok = Versions.rename("same", "same")
    end

    test "returns :not_found when renaming a missing version" do
      assert {:error, :not_found} = Versions.rename("missing", "anywhere")
    end

    test "rejects an invalid new name" do
      {:ok, _} = Versions.save("ok", %{})
      assert {:error, :invalid_name} = Versions.rename("ok", "")
    end
  end

  describe "merge_with_defaults/1" do
    test "fills in missing keys from defaults" do
      saved = %{"patio_length" => 5500}
      merged = Versions.merge_with_defaults(saved)

      assert merged["patio_length"] == 5500
      # Default values still present:
      assert Map.has_key?(merged, "patio_width")
      assert Map.has_key?(merged, "board_width")
    end
  end

  describe "tolerance" do
    test "missing file is treated as empty", %{path: path} do
      File.rm(path)
      assert Versions.list() == []
    end

    test "corrupt JSON is treated as empty", %{path: path} do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "{ this is not json")
      assert Versions.list() == []
    end
  end
end
