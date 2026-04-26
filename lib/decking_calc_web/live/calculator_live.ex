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
    params = normalize_checkbox(params, "transverse_frame_enabled")

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
              field={@form[:patio_length]}
              label="Length (mm)"
              error={@errors[:patio_length]}
            />
            <.number_field
              field={@form[:patio_width]}
              label="Width (mm)"
              error={@errors[:patio_width]}
            />
          </div>

          <h2 class="text-lg font-semibold pt-2">Boards</h2>
          <div class="grid grid-cols-2 gap-3">
            <.number_field
              field={@form[:board_width]}
              label="Board width (mm)"
              error={@errors[:board_width]}
            />
            <.number_field
              field={@form[:board_thickness]}
              label="Thickness (mm)"
              error={@errors[:board_thickness]}
            />
          </div>
          <.text_field
            field={@form[:stock_lengths]}
            label="Stock lengths (mm, comma separated)"
            error={@errors[:stock_lengths]}
          />
          <div class="grid grid-cols-2 gap-3">
            <.number_field field={@form[:gap]} label="Side gap (mm)" error={@errors[:gap]} />
            <.number_field
              field={@form[:end_gap]}
              label="End butt gap (mm)"
              error={@errors[:end_gap]}
            />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <.number_field field={@form[:kerf]} label="Kerf (mm)" error={@errors[:kerf]} />
            <.number_field
              field={@form[:min_reuse]}
              label="Min. reusable offcut (mm)"
              error={@errors[:min_reuse]}
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
            field={@form[:max_joist_spacing]}
            label="Max joist spacing (mm)"
            error={@errors[:max_joist_spacing]}
          />

          <h2 class="text-lg font-semibold pt-2">Picture frame</h2>
          <p class="text-xs text-base-content/70 -mt-2">
            Adds end-cap boards laid perpendicular to the field boards at each
            end of the run, hiding the cut ends. No long-side borders.
          </p>
          <label class="label cursor-pointer justify-start gap-3">
            <input type="hidden" name="calc[picture_frame_enabled]" value="false" />
            <input
              type="checkbox"
              name="calc[picture_frame_enabled]"
              value="true"
              class="checkbox"
              checked={checked?(@form[:picture_frame_enabled].value)}
            />
            <span class="label-text">Enable picture-frame end caps</span>
          </label>
          <div class="grid grid-cols-2 gap-3">
            <.number_field
              field={@form[:picture_frame_border_boards]}
              label="Cap boards per end"
              error={@errors[:picture_frame]}
            />
          </div>

          <h2 class="text-lg font-semibold pt-2">Transverse breaker frame</h2>
          <p class="text-xs text-base-content/70 -mt-2">
            Adds a transverse band that splits the field along its length so each
            field row fits within stock. Only applied when boards run along the
            length. Segment count is derived automatically.
          </p>
          <label class="label cursor-pointer justify-start gap-3">
            <input type="hidden" name="calc[transverse_frame_enabled]" value="false" />
            <input
              type="checkbox"
              name="calc[transverse_frame_enabled]"
              value="true"
              class="checkbox"
              checked={checked?(@form[:transverse_frame_enabled].value)}
            />
            <span class="label-text">Enable transverse breaker frame</span>
          </label>
          <div class="grid grid-cols-2 gap-3">
            <.number_field
              field={@form[:transverse_band_boards]}
              label="Band boards per breaker"
              error={@errors[:transverse_frame]}
            />
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
        <.stat label="Field rows" value={@result.summary.field_rows} />
        <.stat
          label="Row length"
          value={"#{fmt_length(field_row_length(@result))}"}
        />
        <.stat label="Last-row width" value={"#{@result.layout.last_row_width} mm"} />
        <.stat label="Joists" value={@result.joists.joist_count} />
        <.stat
          label="Joist spacing"
          value={"#{@result.joists.actual_spacing} mm (≤ #{@result.input.max_joist_spacing})"}
        />
        <.stat
          label="Waste"
          value={"#{fmt_length(@result.summary.total_waste)} (#{@result.summary.waste_pct}%)"}
        />
        <%= if @result.transverse_frame do %>
          <.stat
            label="Segments"
            value={"#{@result.summary.segments} × #{fmt_length(@result.transverse_frame.segment_length)}"}
          />
          <.stat
            label="Breaker bands"
            value={"#{@result.transverse_frame.band_count} × #{@result.transverse_frame.band_boards} board(s)"}
          />
        <% end %>
      </div>

      <h3 class="font-semibold">Layout</h3>
      <.diagram result={@result} />

      <h3 class="font-semibold">Boards to purchase</h3>
      <ul class="list-disc list-inside text-sm">
        <%= for {len, n} <- Enum.sort_by(@result.summary.boards_by_stock, fn {l, _} -> -l end) do %>
          <li>
            <strong>{n}</strong> × <strong>{fmt_length(len)}</strong> boards
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
                <td class="text-right">{fmt_length(row.row_length)}</td>
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

      <%= if @result.cut_list.unused_offcuts != [] do %>
        <p class="text-xs text-base-content/70">
          Remaining usable offcuts: {Enum.map_join(
            @result.cut_list.unused_offcuts,
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

  attr :result, :map, required: true

  defp diagram(assigns) do
    g = build_diagram(assigns.result)
    assigns = assign(assigns, :g, g)

    ~H"""
    <figure class="bg-base-100 rounded-lg p-2 border border-base-300">
      <svg
        viewBox={"0 0 #{@g.view_w} #{@g.view_h}"}
        class="w-full h-auto"
        preserveAspectRatio="xMidYMid meet"
        role="img"
        aria-label="Decking layout diagram"
      >
        <!-- Patio outline -->
        <rect
          x="0"
          y="0"
          width={@g.view_w}
          height={@g.view_h}
          class="fill-base-200 stroke-base-content"
          stroke-width={@g.stroke}
        />
        
    <!-- Picture-frame end caps (only on sides perpendicular to board direction) -->
        <%= if @g.has_picture_frame do %>
          <rect
            x={@g.inset_x}
            y={@g.inset_y}
            width={@g.view_w - 2 * @g.inset_x}
            height={@g.view_h - 2 * @g.inset_y}
            class="fill-base-100 stroke-base-content"
            stroke-width={@g.stroke}
          />
        <% end %>
        
    <!-- Field rows -->
        <%= for row <- @g.rows do %>
          <rect
            x={row.x}
            y={row.y}
            width={row.w}
            height={row.h}
            class="fill-warning/30 stroke-warning"
            stroke-width={@g.thin_stroke}
          />
        <% end %>
        
    <!-- Breaker bands (drawn last so they sit above field rows) -->
        <%= for band <- @g.bands do %>
          <rect
            x={band.x}
            y={band.y}
            width={band.w}
            height={band.h}
            class="fill-secondary/80 stroke-secondary"
            stroke-width={@g.stroke}
          />
        <% end %>
      </svg>
      <figcaption class="text-xs text-base-content/70 mt-1">
        {@g.caption}
      </figcaption>
    </figure>
    """
  end

  # Build a coordinate-system-agnostic plan for the SVG. All values are in mm,
  # rendered into a viewBox of patio_length × patio_width.
  defp build_diagram(result) do
    input = result.input
    layout = result.layout
    view_w = input.patio_length
    view_h = input.patio_width
    has_pf = result.picture_frame != nil

    inset =
      case result.picture_frame do
        nil -> 0
        %{border_boards: n} -> n * input.board_width + n * input.gap
      end

    # End caps inset only the axis along which boards run; the perpendicular
    # axis is unchanged.
    {inset_x, inset_y} =
      case input.board_direction do
        :along_length -> {inset, 0}
        :along_width -> {0, inset}
      end

    {rows, bands} =
      diagram_rows_and_bands(input, layout, result.transverse_frame, inset_x, inset_y)

    caption =
      cond do
        result.transverse_frame ->
          tf = result.transverse_frame

          "#{input.patio_length} × #{input.patio_width} mm — " <>
            "#{tf.segments} segments × #{tf.segment_length} mm, " <>
            "#{tf.band_count} breaker band(s) of #{tf.band_thickness} mm"

        has_pf ->
          "#{input.patio_length} × #{input.patio_width} mm — picture-frame end caps #{inset} mm thick"

        true ->
          "#{input.patio_length} × #{input.patio_width} mm"
      end

    # Stroke widths scaled to the larger axis so they remain visible
    # regardless of patio size.
    base_stroke = max(div(max(view_w, view_h), 400), 1)

    %{
      view_w: view_w,
      view_h: view_h,
      inset: inset,
      inset_x: inset_x,
      inset_y: inset_y,
      has_picture_frame: has_pf,
      rows: rows,
      bands: bands,
      stroke: base_stroke * 2,
      thin_stroke: base_stroke,
      caption: caption
    }
  end

  defp diagram_rows_and_bands(input, layout, transverse_frame, inset_x, inset_y) do
    bw = input.board_width
    gap = input.gap
    row_count = layout.row_count

    case input.board_direction do
      :along_length ->
        rows =
          for i <- 1..max(row_count, 0) do
            h = if i == row_count, do: layout.last_row_width, else: bw
            %{x: inset_x, y: inset_y + (i - 1) * (bw + gap), w: layout.field_length, h: h}
          end

        bands =
          case transverse_frame do
            nil ->
              []

            %{band_count: bc, band_thickness: bt, segment_length: sl} when bc > 0 ->
              for d <- 1..bc do
                x = inset_x + d * sl + (d - 1) * (bt + 2 * input.end_gap) + input.end_gap
                %{x: x, y: inset_y, w: bt, h: layout.field_width}
              end

            _ ->
              []
          end

        {rows, bands}

      :along_width ->
        # Boards run along Y axis. layout.field_length corresponds to
        # patio_width; layout.field_width corresponds to patio_length.
        rows =
          for i <- 1..max(row_count, 0) do
            w = if i == row_count, do: layout.last_row_width, else: bw
            %{x: inset_x + (i - 1) * (bw + gap), y: inset_y, w: w, h: layout.field_length}
          end

        # Transverse frame is not produced for along_width, but be defensive.
        {rows, []}
    end
  end

  defp format_row_id({:field, i}), do: "field #{i}"
  defp format_row_id({:field, s, i}), do: "seg #{s} field #{i}"
  defp format_row_id({:border_cap, i}), do: "end cap #{i}"
  defp format_row_id({:band, d, i}), do: "breaker #{d} board #{i}"
  defp format_row_id(other), do: inspect(other)

  defp field_row_length(%{transverse_frame: %{segment_length: sl}}), do: sl
  defp field_row_length(%{layout: %{row_length: rl}}), do: rl

  defp format_cut(%{source: :stock, stock_length: sl, length: l}) do
    "stock #{sl} → #{l} mm"
  end

  defp format_cut(%{source: :offcut, length: l}) do
    "offcut → #{l} mm"
  end

  defp fmt_length(mm) when is_integer(mm) do
    if mm >= 1000 do
      whole = div(mm, 1000)
      rem = rem(mm, 1000)
      "#{whole}.#{pad(rem)} m"
    else
      "#{mm} mm"
    end
  end

  defp fmt_length(other), do: to_string(other)

  defp pad(n) when n < 10, do: "00#{n}"
  defp pad(n) when n < 100, do: "0#{n}"
  defp pad(n), do: "#{n}"

  defp checked?(true), do: true
  defp checked?("true"), do: true
  defp checked?("on"), do: true
  defp checked?(_), do: false
end
