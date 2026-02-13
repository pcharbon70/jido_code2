defmodule JidoCodeWeb.SetupLive do
  use JidoCodeWeb, :live_view

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User
  alias JidoCode.Setup.OwnerBootstrap
  alias JidoCode.Setup.PrerequisiteChecks
  alias JidoCode.Setup.RuntimeMode
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
  @owner_step_validation_error "Complete owner account bootstrap before continuing."

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

    prerequisite_report = resolve_prerequisite_report(onboarding_step, onboarding_state)
    owner_bootstrap = resolve_owner_bootstrap(onboarding_step)

    {:ok,
     socket
     |> assign(:onboarding_step, onboarding_step)
     |> assign(:onboarding_state, onboarding_state)
     |> assign(:prerequisite_report, prerequisite_report)
     |> assign(:owner_bootstrap, owner_bootstrap)
     |> assign(:save_error, owner_bootstrap_error(owner_bootstrap))
     |> assign(:redirect_reason, params["reason"] || "onboarding_incomplete")
     |> assign(:diagnostic, diagnostic)
     |> assign_step_form(onboarding_step, onboarding_state)
     |> assign_owner_form(onboarding_step, onboarding_state, owner_bootstrap)}
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

        <section :if={@prerequisite_report} id="setup-prerequisite-status" class="space-y-3">
          <h2 class="text-lg font-semibold">System prerequisite checks</h2>
          <p id="setup-prerequisite-checked-at" class="text-sm text-base-content/70">
            Last checked: {format_checked_at(@prerequisite_report.checked_at)}
          </p>

          <ul class="space-y-2">
            <li
              :for={check <- @prerequisite_report.checks}
              id={"setup-prerequisite-#{check.id}"}
              class="rounded-lg border border-base-300 bg-base-100 p-3"
            >
              <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
                <p class="font-medium">{check.name}</p>
                <span
                  id={"setup-prerequisite-#{check.id}-status"}
                  class={["badge", prerequisite_status_class(check.status)]}
                >
                  {prerequisite_status_label(check.status)}
                </span>
              </div>
              <p class="text-sm text-base-content/80">{check.detail}</p>
              <p
                :if={check.status != :pass}
                id={"setup-prerequisite-remediation-#{check.id}"}
                class="text-sm text-warning"
              >
                {check.remediation}
              </p>
            </li>
          </ul>
        </section>

        <section :if={@onboarding_step == 2} id="setup-owner-bootstrap" class="space-y-3">
          <h2 class="text-lg font-semibold">Owner account bootstrap</h2>
          <p id="setup-owner-bootstrap-mode" class="text-sm text-base-content/80">
            {owner_bootstrap_mode_message(@owner_bootstrap.mode)}
          </p>
          <p
            :if={@owner_bootstrap.mode == :confirm and @owner_bootstrap.owner_email}
            id="setup-owner-bootstrap-owner-email"
            class="font-mono text-sm"
          >
            Existing owner: {@owner_bootstrap.owner_email}
          </p>

          <.form for={@owner_form} id="setup-owner-bootstrap-form" phx-submit="bootstrap_owner" class="space-y-4">
            <.input
              field={@owner_form[:email]}
              id="setup-owner-email"
              type="email"
              label="Owner email"
              required
            />
            <.input
              field={@owner_form[:password]}
              id="setup-owner-password"
              type="password"
              label={owner_password_label(@owner_bootstrap.mode)}
              required
            />
            <.input
              :if={@owner_bootstrap.mode == :create}
              field={@owner_form[:password_confirmation]}
              id="setup-owner-password-confirmation"
              type="password"
              label="Confirm owner password"
              required
            />
            <button id="setup-owner-bootstrap-submit" type="submit" class="btn btn-primary">
              {owner_submit_label(@owner_bootstrap.mode)}
            </button>
          </.form>
        </section>

        <.form
          :if={@onboarding_step != 2}
          for={@step_form}
          id="onboarding-step-form"
          phx-submit="save_step"
          class="space-y-4"
        >
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
  def handle_event("save_step", _params, %{assigns: %{onboarding_step: 2}} = socket) do
    {:noreply, assign(socket, :save_error, @owner_step_validation_error)}
  end

  def handle_event("bootstrap_owner", %{"owner" => owner_params}, socket) do
    case OwnerBootstrap.bootstrap(owner_params) do
      {:ok, owner_bootstrap_result} ->
        step_state =
          %{
            "validated_note" => owner_bootstrap_result.validated_note,
            "owner_email" => to_string(owner_bootstrap_result.owner.email),
            "owner_mode" => Atom.to_string(owner_bootstrap_result.owner_mode)
          }
          |> maybe_mark_registration_lockout()

        case SystemConfig.save_step_progress(step_state) do
          {:ok, %SystemConfig{} = config} ->
            {:noreply,
             socket
             |> assign_config_state(config)
             |> assign(:save_error, nil)
             |> redirect(to: owner_sign_in_with_token_path(owner_bootstrap_result.token))}

          {:error, %{diagnostic: diagnostic}} ->
            {:noreply, assign(socket, :save_error, diagnostic)}
        end

      {:error, {_error_type, diagnostic}} ->
        owner_bootstrap = resolve_owner_bootstrap(socket.assigns.onboarding_step)

        {:noreply,
         socket
         |> assign(:owner_bootstrap, owner_bootstrap)
         |> assign(:save_error, diagnostic)
         |> assign_owner_form(
           socket.assigns.onboarding_step,
           socket.assigns.onboarding_state,
           owner_bootstrap,
           owner_params
         )}
    end
  end

  def handle_event("bootstrap_owner", _params, socket) do
    {:noreply, assign(socket, :save_error, @owner_step_validation_error)}
  end

  def handle_event("save_step", %{"step" => %{"validated_note" => validated_note}}, socket) do
    case normalize_validated_note(validated_note) do
      {:ok, normalized_note} ->
        save_step_progress(socket, normalized_note)

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
      |> fetch_step_state(onboarding_step)
      |> Map.get("validated_note", "")

    assign(socket, :step_form, to_form(%{"validated_note" => persisted_note}, as: :step))
  end

  defp assign_owner_form(
         socket,
         onboarding_step,
         onboarding_state,
         owner_bootstrap,
         owner_params \\ %{}
       ) do
    if onboarding_step == 2 do
      persisted_owner_email =
        onboarding_state
        |> fetch_step_state(2)
        |> Map.get("owner_email", "")

      owner_email =
        owner_params["email"] ||
          owner_bootstrap.owner_email ||
          persisted_owner_email

      assign(
        socket,
        :owner_form,
        to_form(
          %{
            "email" => owner_email,
            "password" => "",
            "password_confirmation" => ""
          },
          as: :owner
        )
      )
    else
      assign(
        socket,
        :owner_form,
        to_form(%{"email" => "", "password" => "", "password_confirmation" => ""}, as: :owner)
      )
    end
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

  defp resolve_prerequisite_report(onboarding_step, onboarding_state) do
    if onboarding_step == 1 do
      PrerequisiteChecks.run()
    else
      onboarding_state
      |> fetch_step_state(1)
      |> Map.get("prerequisite_checks")
      |> PrerequisiteChecks.from_state()
    end
  end

  defp save_step_progress(socket, validated_note) do
    if socket.assigns.onboarding_step == 1 do
      prerequisite_report = PrerequisiteChecks.run()

      socket = assign(socket, :prerequisite_report, prerequisite_report)

      if PrerequisiteChecks.blocked?(prerequisite_report) do
        {:noreply, assign(socket, :save_error, prerequisite_block_message(prerequisite_report))}
      else
        persist_step_progress(socket, %{
          "validated_note" => validated_note,
          "prerequisite_checks" => PrerequisiteChecks.serialize_for_state(prerequisite_report)
        })
      end
    else
      persist_step_progress(socket, %{"validated_note" => validated_note})
    end
  end

  defp persist_step_progress(socket, step_state) do
    case SystemConfig.save_step_progress(step_state) do
      {:ok, %SystemConfig{} = config} ->
        {:noreply,
         socket
         |> assign_config_state(config)
         |> assign(:save_error, nil)
         |> assign_step_form(config.onboarding_step, config.onboarding_state)}

      {:error, %{diagnostic: diagnostic}} ->
        {:noreply, assign(socket, :save_error, diagnostic)}
    end
  end

  defp prerequisite_block_message(report) do
    blocked_checks = PrerequisiteChecks.blocked_checks(report)

    remediation =
      blocked_checks
      |> Enum.map(fn check -> "#{check.name}: #{check.remediation}" end)
      |> Enum.join(" ")

    timeout_blocked? = Enum.any?(blocked_checks, fn check -> check.status == :timeout end)

    prefix =
      if timeout_blocked? do
        "One or more prerequisite checks timed out. Onboarding remains blocked and no setup progress was saved."
      else
        "System prerequisite checks failed. Resolve the reported prerequisites before continuing."
      end

    String.trim("#{prefix} #{remediation}")
  end

  defp prerequisite_status_label(:pass), do: "Pass"
  defp prerequisite_status_label(:timeout), do: "Timeout"
  defp prerequisite_status_label(:fail), do: "Fail"

  defp prerequisite_status_class(:pass), do: "badge-success"
  defp prerequisite_status_class(:timeout), do: "badge-warning"
  defp prerequisite_status_class(:fail), do: "badge-error"

  defp format_checked_at(%DateTime{} = checked_at), do: DateTime.to_iso8601(checked_at)
  defp format_checked_at(_), do: "unknown"

  defp fetch_step_state(onboarding_state, onboarding_step) when is_map(onboarding_state) do
    step_key = Integer.to_string(onboarding_step)
    Map.get(onboarding_state, step_key) || Map.get(onboarding_state, onboarding_step) || %{}
  end

  defp fetch_step_state(_onboarding_state, _onboarding_step), do: %{}

  defp step_title(step) do
    Map.get(@wizard_steps, step, "Onboarding step #{step}")
  end

  defp assign_config_state(socket, %SystemConfig{} = config) do
    owner_bootstrap = resolve_owner_bootstrap(config.onboarding_step)

    socket
    |> assign(:onboarding_step, config.onboarding_step)
    |> assign(:onboarding_state, config.onboarding_state)
    |> assign(
      :prerequisite_report,
      resolve_prerequisite_report(config.onboarding_step, config.onboarding_state)
    )
    |> assign(:owner_bootstrap, owner_bootstrap)
    |> assign_owner_form(config.onboarding_step, config.onboarding_state, owner_bootstrap)
  end

  defp resolve_owner_bootstrap(2) do
    case OwnerBootstrap.status() do
      {:ok, %{mode: :create}} ->
        %{mode: :create, owner_email: nil, error: nil}

      {:ok, %{mode: :confirm, owner: owner}} ->
        %{mode: :confirm, owner_email: to_string(owner.email), error: nil}

      {:error, {_error_type, diagnostic}} ->
        %{mode: :error, owner_email: nil, error: diagnostic}
    end
  end

  defp resolve_owner_bootstrap(_step), do: %{mode: :inactive, owner_email: nil, error: nil}

  defp owner_bootstrap_error(%{error: diagnostic})
       when is_binary(diagnostic) and diagnostic != "",
       do: diagnostic

  defp owner_bootstrap_error(_owner_bootstrap), do: nil

  defp owner_bootstrap_mode_message(:create),
    do: "No owner account exists yet. Create one owner to continue."

  defp owner_bootstrap_mode_message(:confirm),
    do: "An owner account already exists. Confirm owner credentials to continue."

  defp owner_bootstrap_mode_message(:error),
    do: "Owner bootstrap is currently blocked by a single-user policy issue."

  defp owner_bootstrap_mode_message(:inactive), do: ""

  defp owner_password_label(:create), do: "Owner password"
  defp owner_password_label(:confirm), do: "Owner password for confirmation"
  defp owner_password_label(_mode), do: "Owner password"

  defp owner_submit_label(:create), do: "Create owner account"
  defp owner_submit_label(:confirm), do: "Confirm owner account"
  defp owner_submit_label(_mode), do: "Continue"

  defp maybe_mark_registration_lockout(step_state) do
    if RuntimeMode.production?() do
      Map.put(step_state, "registration_actions_disabled", true)
    else
      step_state
    end
  end

  defp owner_sign_in_with_token_path(token) do
    strategy = Info.strategy!(User, :password)

    strategy_path =
      strategy
      |> Strategy.routes()
      |> Enum.find_value(fn
        {path, :sign_in_with_token} -> path
        _ -> nil
      end)

    path =
      Path.join(
        "/auth",
        String.trim_leading(strategy_path || "/user/password/sign_in_with_token", "/")
      )

    query = URI.encode_query(%{"token" => token})

    "#{path}?#{query}"
  end

  defp step_number(step_key), do: parse_step(step_key)
end
