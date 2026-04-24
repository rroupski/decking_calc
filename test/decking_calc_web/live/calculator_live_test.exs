defmodule DeckingCalcWeb.CalculatorLiveTest do
  use DeckingCalcWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "mounts and renders the calculator form with default results", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Decking layout calculator"
    assert html =~ "Patio"
    assert html =~ "Boards to purchase"
  end

  test "updates results when inputs change", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    html =
      view
      |> form("form", calc: %{"patio_length_mm" => "6000", "patio_width_mm" => "4500"})
      |> render_change()

    assert html =~ "Field rows"
  end
end
