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
      |> form("#calculator-form", calc: %{"patio_length" => "4000", "patio_width" => "4500"})
      |> render_change()

    assert html =~ "Field rows"
  end

  # ── Optimize-width feature ────────────────────────────────────────────────
  #
  # Scenario: patio_width=3500, board_width=150, gap=5
  #   pitch = 155, row_count = div(3505, 155) = 22
  #   used  = 22×150 + 21×5 = 3405, margin = 95 > 5
  #   → last_row_width = 240 mm (ripped)
  #   shrink_to = 3405, grow_to = 3560
  #   95 (current-shrink) > 60 (grow-current) → optimise picks grow → 3560
  #
  # After optimising to 3560:
  #   row_count = div(3565, 155) = 23, used = 23×150 + 22×5 = 3560, margin = 0
  #   → last_row_width = 150 mm (full board, no rip)

  test "warning banner is shown when last row requires ripping", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    html =
      view
      |> form("#calculator-form",
        calc: %{"patio_width" => "3500", "board_width" => "150", "gap" => "5"}
      )
      |> render_change()

    assert html =~ "being ripped to"
    assert has_element?(view, "[phx-click='optimize_width']")
  end

  test "warning banner is absent when layout is an exact fit", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # 3560 = 23×150 + 22×5 — perfect fit, margin 0
    html =
      view
      |> form("#calculator-form",
        calc: %{"patio_width" => "3560", "board_width" => "150", "gap" => "5"}
      )
      |> render_change()

    refute html =~ "being ripped to"
    refute has_element?(view, "[phx-click='optimize_width']")
  end

  test "optimize_width snaps patio_width to grow candidate when it is closer", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # Bring view to the ripped state (grow candidate is 3560, 60 mm away)
    view
    |> form("#calculator-form",
      calc: %{"patio_width" => "3500", "board_width" => "150", "gap" => "5"}
    )
    |> render_change()

    # Click the button
    html = view |> element("[phx-click='optimize_width']") |> render_click()

    # Banner should be gone and patio_width input should show 3560
    refute html =~ "being ripped to"
    assert has_element?(view, "input[name='calc[patio_width]'][value='3560']")
  end

  test "optimize_width snaps patio_width to shrink candidate when it is closer", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # patio_width=3415: shrink=3405 (10 away), grow=3560 (145 away) → shrink wins
    view
    |> form("#calculator-form",
      calc: %{"patio_width" => "3415", "board_width" => "150", "gap" => "5"}
    )
    |> render_change()

    html = view |> element("[phx-click='optimize_width']") |> render_click()

    refute html =~ "being ripped to"
    assert has_element?(view, "input[name='calc[patio_width]'][value='3405']")
  end

  test "optimize_width adjusts patio_length when boards run along_width", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # along_width: rows stack across patio_length, which becomes the short axis.
    # patio_length=3500, board_width=150, gap=5 → same arithmetic as above → grow to 3560
    view
    |> form("#calculator-form",
      calc: %{
        "patio_length" => "3500",
        "patio_width" => "4000",
        "board_width" => "150",
        "gap" => "5",
        "board_direction" => "along_width"
      }
    )
    |> render_change()

    html = view |> element("[phx-click='optimize_width']") |> render_click()

    refute html =~ "being ripped to"
    assert has_element?(view, "input[name='calc[patio_length]'][value='3560']")
  end
end
