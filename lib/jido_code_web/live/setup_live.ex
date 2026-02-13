defmodule JidoCodeWeb.SetupLive do
  use JidoCodeWeb, :live_view

  alias JidoCode.Setup.SystemConfig

  @wizard_steps %{
    1 => "Welcome and system check",
    2 => "Owner account bootstrap",
    3 => "Provider and secret setup",
    4 => "GitHub app and webhook validation",
    5 => "Environment defaults",
    6 => "Issue bot MVP checks",
    7 => "Import first project",
    8 => "Complete onboarding"
  }

  @default_diagnostic "Setup is required before protected routes are available."
  @validation_error "Add validation notes before continuing."

  @impl true
  def mount(params, _session, socket) do
    parsed_step = parse_step(params["step"])

    {onboarding_step, onboarding_state, diagnostic} =
      case SystemConfig.load() do
        {:ok, %SystemConfig{} = config} ->
          {config.onboarding_step, config.onboarding_state, params["diagnostic"] || @default_diagnostic}

        {:error, %{diagnostic: load_diagnostic}} ->
          {parsed_step, %{}, params["diagnostic"] || load_diagnostic}
      end

    {:ok,
     socket
     |> assign(:onboarding_step, onboarding_step)
     |> assign(:onboarding_state, onboarding_state)
     |> assign(:save_error, nil)
     |> assign(:redirect_reason, params["reason"] || "onboarding_incomplete")
     |> assign(:diagnostic, diagnostic)
     |> assign_step_form(onboarding_step, onboarding_state)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <section id="setup-gate" class="mx-auto w-full max-w-3xl space-y-4">
        <h1 class="text-2xl font-semibold">Setup required</h1>
        <p class="text-base-content/80">
          Complete onboarding before accessing protected routes.
        </p>

        <dl class="space-y-3 rounded-lg border border-base-300 bg-base-100 p-4">
          <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
            <dt class="font-medium">Resolved onboarding step</dt>
            <dd id="resolved-onboarding-step" class="font-mono">Step {@onboarding_step}</dd>
          </div>
          <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
            <dt class="font-medium">Current wizard step</dt>
            <dd id="current-wizard-step" class="font-mono">{step_title(@onboarding_step)}</dd>
          </div>
          <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
            <dt class="font-medium">Redirect reason</dt>
            <dd id="setup-redirect-reason" class="font-mono">{@redirect_reason}</dd>
          </div>
        </dl>

        <div id="setup-diagnostic" class="alert alert-warning">
          <.icon name="hero-exclamation-triangle-mini" class="size-5" />
          <span>{@diagnostic}</span>
        </div>

        <div :if={@save_error} id="setup-save-error" class="alert alert-error">
          <.icon name="hero-x-circle-mini" class="size-5" />
          <span>{@save_error}</span>
        </div>

        <.form for={@step_form} id="onboarding-step-form" phx-submit="save_step" class="space-y-4">
          <.input
            field={@step_form[:validated_note]}
            id="onboarding-validated-note"
            type="text"
            label="Validation notes for this step"
            required
          />
          <button id="onboarding-save-step" type="submit" class="btn btn-primary">
            Save step and continue
          </button>
        </.form>

        <section id="validated-state" class="space-y-2">
          <h2 class="text-lg font-semibold">Persisted validated state</h2>
          <p :if={Enum.empty?(validated_step_entries(@onboarding_state))} class="text-sm text-base-content/70">
            No step state has been validated yet.
          </p>
          <ul :if={!Enum.empty?(validated_step_entries(@onboarding_state))} class="space-y-2">
            <li
              :for={{step_key, step_state} <- validated_step_entries(@onboarding_state)}
              id={"validated-state-step-#{step_number(step_key)}"}
              class="rounded-lg border border-base-300 bg-base-100 p-3"
            >
              <p class="font-medium">Step {step_number(step_key)}</p>
              <p class="text-sm text-base-content/80">{Map.get(step_state, "validated_note", "Validated")}</p>
            </li>
          </ul>
        </section>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("save_step", %{"step" => %{"validated_note" => validated_note}}, socket) do
    case normalize_validated_note(validated_note) do
      {:ok, normalized_note} ->
        case SystemConfig.save_step_progress(%{"validated_note" => normalized_note}) do
          {:ok, %SystemConfig{} = config} ->
            {:noreply,
             socket
             |> assign(:onboarding_step, config.onboarding_step)
             |> assign(:onboarding_state, config.onboarding_state)
             |> assign(:save_error, nil)
             |> assign_step_form(config.onboarding_step, config.onboarding_state)}

          {:error, %{diagnostic: diagnostic}} ->
            {:noreply, assign(socket, :save_error, diagnostic)}
        end

      {:error, diagnostic} ->
        {:noreply, assign(socket, :save_error, diagnostic)}
    end
  end

  def handle_event("save_step", _params, socket) do
    {:noreply, assign(socket, :save_error, @validation_error)}
  end

  defp parse_step(step) when is_integer(step) and step > 0, do: step

  defp parse_step(step) when is_binary(step) do
    case Integer.parse(step) do
      {parsed_step, ""} when parsed_step > 0 -> parsed_step
      _ -> 1
    end
  end

  defp parse_step(_), do: 1

  defp assign_step_form(socket, onboarding_step, onboarding_state) do
    persisted_note =
      onboarding_state
      |> Map.get(Integer.to_string(onboarding_step), %{})
      |> Map.get("validated_note", "")

    assign(socket, :step_form, to_form(%{"validated_note" => persisted_note}, as: :step))
  end

  defp normalize_validated_note(validated_note) when is_binary(validated_note) do
    normalized_note = String.trim(validated_note)

    if normalized_note == "" do
      {:error, @validation_error}
    else
      {:ok, normalized_note}
    end
  end

  defp normalize_validated_note(_), do: {:error, @validation_error}

  defp validated_step_entries(onboarding_state) do
    onboarding_state
    |> Enum.filter(fn {_step_key, step_state} -> is_map(step_state) end)
    |> Enum.sort_by(fn {step_key, _step_state} -> step_number(step_key) end)
  end

  defp step_title(step) do
    Map.get(@wizard_steps, step, "Onboarding step #{step}")
  end

  defp step_number(step_key), do: parse_step(step_key)
end
