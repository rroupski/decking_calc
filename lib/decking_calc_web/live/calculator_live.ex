defmodule DeckingCalcWeb.CalculatorLive do
  @moduledoc """
  Interactive decking layout calculator.
  """
  use DeckingCalcWeb, :live_view

  alias DeckingCalc.{Calculator, Input}

  @impl true
  def mount(_params, _session, socket) do
    params = Input.default_params()

    {:ok,
     socket
     |> assign(:page_title, "Decking Calculator")
     |> assign_from_params(params)}
  end

  @impl true
  def handle_event("calculate", %{"calc" => params}, socket) do
    {:noreply, assign_from_params(socket, params)}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, assign_from_params(socket, Input.default_params())}
  end

  defp assign_from_params(socket, params) do
    params = normalize_checkbox(params, "picture_frame_enabled")
    params = normalize_checkbox(params, "picture_frame_mitre")

    case Input.new(params) do
      {:ok, input} ->
        result = Calculator.compute(input)

        socket
        |> assign(:params, params)
        |> assign(:form, to_form(params, as: :calc))
        |> assign(:result, result)
        |> assign(:errors, %{})

      {:error, errors} ->
        socket
        |> assign(:params, params)
        |> assign(:form, to_form(params, as: :calc, errors: form_errors(errors)))
        |> assign(:result, nil)
        |> assign(:errors, errors)
    end
  end

  defp normalize_checkbox(params, key) do
    Map.put(params, key, Map.get(params, key, false))
  end

  defp form_errors(errors) do
    Enum.map(errors, fn {field, msg} -> {field, {msg, []}} end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div class="mx-auto max-w-6xl p-4 sm:p-6 lg:p-8 space-y-6">
      <header class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-semibold">Decking layout calculator</h1>
          <p class="text-sm text-base-content/70">
            All dimensions in millimetres. Results update as you type.
          </p>
        </div>
        <Layouts.theme_toggle />
      </header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <.form
          for={@form}
          phx-change="calculate"
          phx-submit="calculate"
          class="card bg-base-200 p-4 sm:p-6 space-y-4"
        >
          <h2 class="text-lg font-semibold">Patio</h2>
          <div class="grid grid-cols-2 gap-3">
            <.number_field
              field={@form[:patio_length_mm]}
              label="Length (mm)"
              error={@errors[:patio_length_mm]}
            />
            <.number_field
              field={@form[:patio_width_mm]}
              label="Width (mm)"
              error={@errors[:patio_width_mm]}
            />
          </div>

          <h2 class="text-lg font-semibold pt-2">Boards</h2>
          <div class="grid grid-cols-2 gap-3">
            <.number_field
              field={@form[:board_width_mm]}
              label="Board width (mm)"
              error={@errors[:board_width_mm]}
            />
            <.number_field
              field={@form[:board_thickness_mm]}
              label="Thickness (mm)"
              error={@errors[:board_thickness_mm]}
            />
          </div>
          <.text_field
            field={@form[:stock_lengths_mm]}
            label="Stock lengths (mm, comma separated)"
            error={@errors[:stock_lengths_mm]}
          />
          <div class="grid grid-cols-2 gap-3">
            <.number_field field={@form[:gap_mm]} label="Side gap (mm)" error={@errors[:gap_mm]} />
            <.number_field
              field={@form[:end_gap_mm]}
              label="End butt gap (mm)"
              error={@errors[:end_gap_mm]}
            />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <.number_field field={@form[:kerf_mm]} label="Kerf (mm)" error={@errors[:kerf_mm]} />
            <.number_field
              field={@form[:min_reuse_mm]}
              label="Min. reusable offcut (mm)"
              error={@errors[:min_reuse_mm]}
            />
          </div>

          <label class="form-control">
            <div class="label"><span class="label-text">Board direction</span></div>
            <select
              name="calc[board_direction]"
              class="select select-bordered"
            >
              <option value="along_length" selected={@form[:board_direction].value == "along_length"}>
                Along length
              </option>
              <option value="along_width" selected={@form[:board_direction].value == "along_width"}>
                Along width
              </option>
            </select>
          </label>

          <h2 class="text-lg font-semibold pt-2">Joists</h2>
          <.number_field
            field={@form[:max_joist_spacing_mm]}
            label="Max joist spacing (mm)"
            error={@errors[:max_joist_spacing_mm]}
          />

          <h2 class="text-lg font-semibold pt-2">Picture frame</h2>
          <label class="label cursor-pointer justify-start gap-3">
            <input type="hidden" name="calc[picture_frame_enabled]" value="false" />
            <input
              type="checkbox"
              name="calc[picture_frame_enabled]"
              value="true"
              class="checkbox"
              checked={checked?(@form[:picture_frame_enabled].value)}
            />
            <span class="label-text">Enable picture-frame border</span>
          </label>
          <div class="grid grid-cols-2 gap-3">
            <.number_field
              field={@form[:picture_frame_border_boards]}
              label="Border boards per side"
              error={@errors[:picture_frame]}
            />
            <label class="label cursor-pointer justify-start gap-3">
              <input type="hidden" name="calc[picture_frame_mitre]" value="false" />
              <input
                type="checkbox"
                name="calc[picture_frame_mitre]"
                value="true"
                class="checkbox"
                checked={checked?(@form[:picture_frame_mitre].value)}
              />
              <span class="label-text">Mitred corners</span>
            </label>
          </div>

          <div class="pt-2">
            <button type="button" phx-click="reset" class="btn btn-ghost btn-sm">
              Reset to defaults
            </button>
          </div>
        </.form>

        <section class="space-y-4">
          <%= if @result do %>
            <.results result={@result} />
          <% else %>
            <div class="card bg-base-200 p-6">
              <p class="text-error">Fix the input errors to see results.</p>
            </div>
          <% end %>
        </section>
      </div>
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :error, :any, default: nil

  defp number_field(assigns) do
    ~H"""
    <label class="form-control">
      <div class="label"><span class="label-text">{@label}</span></div>
      <input
        type="number"
        inputmode="numeric"
        name={@field.name}
        value={@field.value}
        class={["input input-bordered", @error && "input-error"]}
      />
      <%= if @error do %>
        <div class="label"><span class="label-text-alt text-error">{@error}</span></div>
      <% end %>
    </label>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :error, :any, default: nil

  defp text_field(assigns) do
    ~H"""
    <label class="form-control">
      <div class="label"><span class="label-text">{@label}</span></div>
      <input
        type="text"
        name={@field.name}
        value={@field.value}
        class={["input input-bordered", @error && "input-error"]}
      />
      <%= if @error do %>
        <div class="label"><span class="label-text-alt text-error">{@error}</span></div>
      <% end %>
    </label>
    """
  end

  attr :result, :map, required: true

  defp results(assigns) do
    ~H"""
    <div class="card bg-base-200 p-4 sm:p-6 space-y-4">
      <h2 class="text-lg font-semibold">Summary</h2>
      <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
        <.stat label="Field rows" value={@result.layout.row_count} />
        <.stat label="Row length" value={"#{fmt_mm(@result.layout.row_length_mm)}"} />
        <.stat label="Last-row width" value={"#{@result.layout.last_row_width_mm} mm"} />
        <.stat label="Joists" value={@result.joists.joist_count} />
        <.stat
          label="Joist spacing"
          value={"#{@result.joists.actual_spacing_mm} mm (≤ #{@result.input.max_joist_spacing_mm})"}
        />
        <.stat
          label="Waste"
          value={"#{fmt_mm(@result.summary.total_waste_mm)} (#{@result.summary.waste_pct}%)"}
        />
      </div>

      <h3 class="font-semibold">Boards to purchase</h3>
      <ul class="list-disc list-inside text-sm">
        <%= for {len, n} <- Enum.sort_by(@result.summary.boards_by_stock, fn {l, _} -> -l end) do %>
          <li>
            <strong>{n}</strong> × <strong>{fmt_mm(len)}</strong> boards
          </li>
        <% end %>
        <%= if @result.summary.boards_by_stock == %{} do %>
          <li>No boards required.</li>
        <% end %>
      </ul>

      <h3 class="font-semibold">Cut list</h3>
      <div class="overflow-x-auto">
        <table class="table table-zebra table-sm">
          <thead>
            <tr>
              <th>Row</th>
              <th class="text-right">Row length</th>
              <th>Cuts (source · length)</th>
            </tr>
          </thead>
          <tbody>
            <%= for row <- @result.cut_list.rows do %>
              <tr>
                <td class="font-mono">{format_row_id(row.row_id)}</td>
                <td class="text-right">{fmt_mm(row.row_length_mm)}</td>
                <td>
                  <%= for cut <- row.cuts do %>
                    <span class="badge badge-outline badge-sm mr-1 mb-1">
                      {format_cut(cut)}
                    </span>
                  <% end %>
                </td>
              </tr>
            <% end %>
            <%= if @result.cut_list.rows == [] do %>
              <tr>
                <td colspan="3" class="text-base-content/60">No rows to cut.</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <%= if @result.cut_list.unused_offcuts_mm != [] do %>
        <p class="text-xs text-base-content/70">
          Remaining usable offcuts: {Enum.map_join(
            @result.cut_list.unused_offcuts_mm,
            ", ",
            &"#{&1} mm"
          )}
        </p>
      <% end %>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp stat(assigns) do
    ~H"""
    <div class="stat bg-base-100 rounded-lg p-3">
      <div class="stat-title text-xs">{@label}</div>
      <div class="stat-value text-lg">{@value}</div>
    </div>
    """
  end

  defp format_row_id({:field, i}), do: "field #{i}"
  defp format_row_id({:border_long, i}), do: "long border #{i}"
  defp format_row_id({:border_short, i}), do: "short border #{i}"
  defp format_row_id(other), do: inspect(other)

  defp format_cut(%{source: :stock, stock_length_mm: sl, length_mm: l}) do
    "stock #{sl} → #{l} mm"
  end

  defp format_cut(%{source: :offcut, length_mm: l}) do
    "offcut → #{l} mm"
  end

  defp fmt_mm(mm) when is_integer(mm) do
    if mm >= 1000 do
      whole = div(mm, 1000)
      rem = rem(mm, 1000)
      "#{whole}.#{pad(rem)} m"
    else
      "#{mm} mm"
    end
  end

  defp fmt_mm(other), do: to_string(other)

  defp pad(n) when n < 10, do: "00#{n}"
  defp pad(n) when n < 100, do: "0#{n}"
  defp pad(n), do: "#{n}"

  defp checked?(true), do: true
  defp checked?("true"), do: true
  defp checked?("on"), do: true
  defp checked?(_), do: false
end
