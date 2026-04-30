defmodule DeckingCalcWeb.CalculatorLiveVersionsTest do
  # Synchronous because every test mutates the global :versions_path env.
  use DeckingCalcWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "decking_calc_versions_live_#{System.unique_integer([:positive])}.json"
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

    :ok
  end

  test "renders the saved-versions panel", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert html =~ "Saved versions"
    assert has_element?(view, "#save-version-form")
    assert has_element?(view, "#load-version-form")
  end

  test "saves the current input as a named version", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#save-version-form", version: %{"name" => "My patio"})
    |> render_submit()

    assert has_element?(view, "#version-flash", "Saved")
    assert has_element?(view, "select#load-version-select option", "My patio")
    assert has_element?(view, "#delete-version-button")
  end

  test "loads a saved version into the form", %{conn: conn} do
    {:ok, _} = DeckingCalc.Versions.save("Big patio", %{"patio_length" => 9999})

    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#load-version-form", version: %{"name" => "Big patio"})
    |> render_change()

    assert has_element?(view, "input[name='calc[patio_length]'][value='9999']")
    assert has_element?(view, "#version-flash", "Loaded")
  end

  test "marks the loaded version as modified after editing", %{conn: conn} do
    {:ok, _} = DeckingCalc.Versions.save("Editable", %{"patio_length" => 4000})

    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#load-version-form", version: %{"name" => "Editable"})
    |> render_change()

    html =
      view
      |> form("#calculator-form", calc: %{"patio_length" => "4500"})
      |> render_change()

    assert html =~ "modified"
  end

  test "updates an existing version when the name matches the current one", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#save-version-form", version: %{"name" => "Patio A"})
    |> render_submit()

    # Edit and re-save under the same name (form values come back as strings).
    view
    |> form("#calculator-form", calc: %{"patio_length" => "5000"})
    |> render_change()

    view
    |> form("#save-version-form", version: %{"name" => "Patio A"})
    |> render_submit()

    assert {:ok, %{"patio_length" => "5000"}} =
             DeckingCalc.Versions.get("Patio A")

    # Still only one entry.
    assert [%{name: "Patio A"}] = DeckingCalc.Versions.list()
  end

  test "rejects empty names", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#save-version-form", version: %{"name" => "   "})
    |> render_submit()

    assert has_element?(view, "#version-flash", "Enter a name")
  end

  test "deletes the loaded version", %{conn: conn} do
    {:ok, _} = DeckingCalc.Versions.save("Removable", %{"patio_length" => 1234})

    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#load-version-form", version: %{"name" => "Removable"})
    |> render_change()

    view |> element("#delete-version-button") |> render_click()

    assert {:error, :not_found} = DeckingCalc.Versions.get("Removable")
    refute has_element?(view, "#delete-version-button")
    assert has_element?(view, "#version-flash", "Deleted")
  end
end
