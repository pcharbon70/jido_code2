defmodule JidoCodeWeb.SetupLive do
  use JidoCodeWeb, :live_view

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User
  alias JidoCode.Setup.EnvironmentDefaults
  alias JidoCode.Setup.GitHubCredentialChecks
  alias JidoCode.Setup.OwnerBootstrap
  alias JidoCode.Setup.ProviderCredentialChecks
  alias JidoCode.Setup.PrerequisiteChecks
  alias JidoCode.Setup.RuntimeMode
  alias JidoCode.Setup.SystemConfig
  alias JidoCode.Setup.WebhookSimulationChecks

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

    {onboarding_step, onboarding_state, default_environment, workspace_root, diagnostic} =
      case SystemConfig.load() do
        {:ok, %SystemConfig{} = config} ->
          {config.onboarding_step, config.onboarding_state, config.default_environment, config.workspace_root,
           params["diagnostic"] || @default_diagnostic}

        {:error, %{diagnostic: load_diagnostic}} ->
          {parsed_step, %{}, :sprite, nil, params["diagnostic"] || load_diagnostic}
      end

    prerequisite_report = resolve_prerequisite_report(onboarding_step, onboarding_state)

    provider_credential_report =
      resolve_provider_credential_report(onboarding_step, onboarding_state)

    github_credential_report =
      resolve_github_credential_report(onboarding_step, onboarding_state)

    webhook_simulation_report =
      resolve_webhook_simulation_report(onboarding_step, onboarding_state)

    environment_defaults_report =
      resolve_environment_defaults_report(
        onboarding_step,
        onboarding_state,
        default_environment,
        workspace_root
      )

    owner_bootstrap = resolve_owner_bootstrap(onboarding_step)

    {:ok,
     socket
     |> assign(:onboarding_step, onboarding_step)
     |> assign(:onboarding_state, onboarding_state)
     |> assign(:default_environment, default_environment)
     |> assign(:workspace_root, workspace_root)
     |> assign(:prerequisite_report, prerequisite_report)
     |> assign(:provider_credential_report, provider_credential_report)
     |> assign(:github_credential_report, github_credential_report)
     |> assign(:webhook_simulation_report, webhook_simulation_report)
     |> assign(:environment_defaults_report, environment_defaults_report)
     |> assign(:owner_bootstrap, owner_bootstrap)
     |> assign(:save_error, owner_bootstrap_error(owner_bootstrap))
     |> assign(:redirect_reason, params["reason"] || "onboarding_incomplete")
     |> assign(:diagnostic, diagnostic)
     |> assign_step_form(onboarding_step, onboarding_state, default_environment, workspace_root)
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

        <section
          :if={@provider_credential_report}
          id="setup-provider-credentials"
          class="space-y-3"
        >
          <h2 class="text-lg font-semibold">LLM provider credential verification</h2>
          <p id="setup-provider-checked-at" class="text-sm text-base-content/70">
            Last checked: {format_checked_at(@provider_credential_report.checked_at)}
          </p>

          <ul class="space-y-2">
            <li
              :for={credential <- @provider_credential_report.credentials}
              id={"setup-provider-#{provider_dom_id(credential.provider)}"}
              class="rounded-lg border border-base-300 bg-base-100 p-3"
            >
              <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
                <p class="font-medium">{credential.name}</p>
                <span
                  id={"setup-provider-#{provider_dom_id(credential.provider)}-status"}
                  class={["badge", provider_status_class(credential.status)]}
                >
                  {provider_status_label(credential.status)}
                </span>
              </div>
              <p
                id={"setup-provider-transition-#{provider_dom_id(credential.provider)}"}
                class="text-sm text-base-content/80"
              >
                Status transition: {credential.transition}
              </p>
              <p class="text-sm text-base-content/80">{credential.detail}</p>
              <p
                :if={credential.verified_at}
                id={"setup-provider-verified-at-#{provider_dom_id(credential.provider)}"}
                class="text-xs text-base-content/70"
              >
                Verified at: {format_checked_at(credential.verified_at)}
              </p>
              <p
                :if={credential.status != :active}
                id={"setup-provider-remediation-#{provider_dom_id(credential.provider)}"}
                class="text-sm text-warning"
              >
                {credential.remediation}
              </p>
            </li>
          </ul>
        </section>

        <section :if={@github_credential_report} id="setup-github-integration" class="space-y-3">
          <h2 class="text-lg font-semibold">GitHub integration credential validation</h2>
          <p id="setup-github-checked-at" class="text-sm text-base-content/70">
            Last validated: {format_checked_at(@github_credential_report.checked_at)}
          </p>
          <p
            :if={@github_credential_report.owner_context}
            id="setup-github-owner-context"
            class="font-mono text-sm text-base-content/80"
          >
            Owner context: {@github_credential_report.owner_context}
          </p>

          <ul class="space-y-2">
            <li
              :for={path <- @github_credential_report.paths}
              id={"setup-github-#{github_path_dom_id(path.path)}"}
              class="rounded-lg border border-base-300 bg-base-100 p-3"
            >
              <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
                <p class="font-medium">{path.name}</p>
                <span
                  id={"setup-github-#{github_path_dom_id(path.path)}-status"}
                  class={["badge", github_status_class(path.status)]}
                >
                  {github_status_label(path.status)}
                </span>
              </div>
              <p
                id={"setup-github-transition-#{github_path_dom_id(path.path)}"}
                class="text-sm text-base-content/80"
              >
                Status transition: {path.transition}
              </p>
              <p
                id={"setup-github-repository-access-#{github_path_dom_id(path.path)}"}
                class="text-sm text-base-content/80"
              >
                Repository access: {github_repository_access_label(path.repository_access)}
              </p>
              <p
                id={"setup-github-repositories-#{github_path_dom_id(path.path)}"}
                class="text-sm text-base-content/80"
              >
                Accessible repositories: {github_repositories_text(path.repositories)}
              </p>
              <p class="text-sm text-base-content/80">{path.detail}</p>
              <p
                :if={path.validated_at}
                id={"setup-github-validated-at-#{github_path_dom_id(path.path)}"}
                class="text-xs text-base-content/70"
              >
                Validated at: {format_checked_at(path.validated_at)}
              </p>
              <p
                :if={path.error_type}
                id={"setup-github-error-type-#{github_path_dom_id(path.path)}"}
                class="text-sm text-error"
              >
                Typed integration error: {path.error_type}
              </p>
              <p
                :if={path.status != :ready}
                id={"setup-github-remediation-#{github_path_dom_id(path.path)}"}
                class="text-sm text-warning"
              >
                {path.remediation}
              </p>
            </li>
          </ul>
        </section>

        <section :if={@environment_defaults_report} id="setup-environment-defaults" class="space-y-3">
          <h2 class="text-lg font-semibold">Execution environment defaults</h2>
          <p id="setup-environment-checked-at" class="text-sm text-base-content/70">
            Last validated: {format_checked_at(@environment_defaults_report.checked_at)}
          </p>

          <div class="rounded-lg border border-base-300 bg-base-100 p-3">
            <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
              <p class="font-medium">Selected mode</p>
              <span id="setup-environment-mode" class="badge badge-info">
                {environment_mode_label(@environment_defaults_report.mode)}
              </span>
            </div>
            <p id="setup-default-environment" class="text-sm text-base-content/80">
              Default environment: {environment_default_label(@environment_defaults_report.default_environment)}
            </p>
            <p
              :if={@environment_defaults_report.workspace_root}
              id="setup-workspace-root"
              class="text-sm text-base-content/80 font-mono"
            >
              Workspace root: {@environment_defaults_report.workspace_root}
            </p>
          </div>

          <ul class="space-y-2">
            <li
              :for={check <- @environment_defaults_report.checks}
              id={"setup-environment-#{check.id}"}
              class="rounded-lg border border-base-300 bg-base-100 p-3"
            >
              <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
                <p class="font-medium">{check.name}</p>
                <span
                  id={"setup-environment-#{check.id}-status"}
                  class={["badge", environment_check_status_class(check.status)]}
                >
                  {environment_check_status_label(check.status)}
                </span>
              </div>
              <p class="text-sm text-base-content/80">{check.detail}</p>
              <p
                :if={check.status != :ready}
                id={"setup-environment-#{check.id}-remediation"}
                class="text-sm text-warning"
              >
                {check.remediation}
              </p>
            </li>
          </ul>
        </section>

        <section :if={@webhook_simulation_report} id="setup-webhook-simulation" class="space-y-3">
          <h2 class="text-lg font-semibold">Issue Bot webhook simulation readiness</h2>
          <p id="setup-webhook-simulated-at" class="text-sm text-base-content/70">
            Last simulated: {format_checked_at(@webhook_simulation_report.checked_at)}
          </p>

          <div class="rounded-lg border border-base-300 bg-base-100 p-3">
            <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
              <p class="font-medium">Simulation status</p>
              <span
                id="setup-webhook-simulation-status"
                class={["badge", webhook_simulation_status_class(@webhook_simulation_report.status)]}
              >
                {webhook_simulation_status_label(@webhook_simulation_report.status)}
              </span>
            </div>
            <p
              :if={@webhook_simulation_report.failure_reason}
              id="setup-webhook-failure-reason"
              class="text-sm text-error"
            >
              {@webhook_simulation_report.failure_reason}
            </p>
          </div>

          <div
            id="setup-webhook-signature"
            class="rounded-lg border border-base-300 bg-base-100 p-3"
          >
            <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
              <p class="font-medium">Signature verification readiness</p>
              <span
                id="setup-webhook-signature-status"
                class={[
                  "badge",
                  webhook_check_status_class(@webhook_simulation_report.signature.status)
                ]}
              >
                {webhook_check_status_label(@webhook_simulation_report.signature.status)}
              </span>
            </div>
            <p class="text-sm text-base-content/80">{@webhook_simulation_report.signature.detail}</p>
            <p
              :if={@webhook_simulation_report.signature.status != :ready}
              id="setup-webhook-signature-remediation"
              class="text-sm text-warning"
            >
              {@webhook_simulation_report.signature.remediation}
            </p>
          </div>

          <ul class="space-y-2">
            <li
              :for={event <- @webhook_simulation_report.events}
              id={"setup-webhook-event-#{webhook_event_dom_id(event.event)}"}
              class="rounded-lg border border-base-300 bg-base-100 p-3"
            >
              <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
                <p class="font-medium">{event.event}</p>
                <span
                  id={"setup-webhook-event-#{webhook_event_dom_id(event.event)}-status"}
                  class={["badge", webhook_check_status_class(event.status)]}
                >
                  {webhook_check_status_label(event.status)}
                </span>
              </div>
              <p
                id={"setup-webhook-event-#{webhook_event_dom_id(event.event)}-route"}
                class="text-sm text-base-content/80"
              >
                Route readiness: {event.route}
              </p>
              <p class="text-sm text-base-content/80">{event.detail}</p>
              <p
                :if={event.status != :ready}
                id={"setup-webhook-event-#{webhook_event_dom_id(event.event)}-remediation"}
                class="text-sm text-warning"
              >
                {event.remediation}
              </p>
            </li>
          </ul>

          <div
            :if={@webhook_simulation_report.status == :ready}
            id="setup-issue-bot-defaults"
            class="rounded-lg border border-base-300 bg-base-100 p-3"
          >
            <p class="font-medium">Issue Bot defaults ready for enablement</p>
            <p id="setup-issue-bot-default-enabled" class="text-sm text-base-content/80">
              Enabled: {issue_bot_default_enabled(@webhook_simulation_report.issue_bot_defaults)}
            </p>
            <p id="setup-issue-bot-default-approval-mode" class="text-sm text-base-content/80">
              Approval mode: {issue_bot_default_approval_mode(@webhook_simulation_report.issue_bot_defaults)}
            </p>
          </div>
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
            :if={@onboarding_step == 5}
            field={@step_form[:execution_mode]}
            id="setup-execution-mode"
            type="select"
            label="Default execution mode"
            options={[{"Cloud (Sprite default)", "cloud"}, {"Local workspace", "local"}]}
            required
          />
          <.input
            :if={@onboarding_step == 5}
            field={@step_form[:workspace_root]}
            id="setup-workspace-root-input"
            type="text"
            label="Local workspace root"
            placeholder="/absolute/path/to/workspaces"
          />
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

  def handle_event("save_step", %{"step" => step_params}, socket) when is_map(step_params) do
    case normalize_validated_note(Map.get(step_params, "validated_note")) do
      {:ok, normalized_note} ->
        save_step_progress(socket, normalized_note, step_params)

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

  defp assign_step_form(
         socket,
         onboarding_step,
         onboarding_state,
         default_environment,
         workspace_root,
         step_params \\ %{}
       ) do
    step_state = fetch_step_state(onboarding_state, onboarding_step)

    persisted_note = Map.get(step_state, "validated_note", "")

    persisted_environment_state =
      step_state
      |> Map.get("environment_defaults", %{})
      |> normalize_environment_state()

    default_mode = default_environment_mode(default_environment)

    execution_mode =
      step_params
      |> Map.get("execution_mode")
      |> normalize_execution_mode(Map.get(persisted_environment_state, :mode, default_mode))

    workspace_root_value =
      step_params
      |> Map.get("workspace_root")
      |> normalize_workspace_root_input(Map.get(persisted_environment_state, :workspace_root, workspace_root || ""))

    assign(
      socket,
      :step_form,
      to_form(
        %{
          "validated_note" => persisted_note,
          "execution_mode" => execution_mode,
          "workspace_root" => workspace_root_value
        },
        as: :step
      )
    )
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

  defp environment_selection(step_params, default_environment, workspace_root)
       when is_map(step_params) do
    %{
      "mode" =>
        step_params
        |> Map.get("execution_mode")
        |> normalize_execution_mode(default_environment_mode(default_environment)),
      "workspace_root" =>
        step_params
        |> Map.get("workspace_root")
        |> normalize_workspace_root_input(workspace_root)
    }
  end

  defp environment_selection(_step_params, default_environment, workspace_root) do
    %{
      "mode" => default_environment_mode(default_environment),
      "workspace_root" => normalize_workspace_root_input(nil, workspace_root)
    }
  end

  defp normalize_environment_state(environment_state) when is_map(environment_state) do
    %{}
    |> maybe_put_environment_field(
      :mode,
      environment_state
      |> Map.get("mode")
      |> normalize_execution_mode(nil)
    )
    |> maybe_put_environment_field(
      :workspace_root,
      environment_state
      |> Map.get("workspace_root")
      |> normalize_optional_workspace_root()
    )
  end

  defp normalize_environment_state(_environment_state), do: %{}

  defp default_environment_mode(:local), do: "local"
  defp default_environment_mode(_default_environment), do: "cloud"

  defp mode_param(:local), do: "local"
  defp mode_param(:cloud), do: "cloud"

  defp normalize_execution_mode("local", _default_mode), do: "local"
  defp normalize_execution_mode(:local, _default_mode), do: "local"
  defp normalize_execution_mode("cloud", _default_mode), do: "cloud"
  defp normalize_execution_mode(:cloud, _default_mode), do: "cloud"
  defp normalize_execution_mode(_mode, nil), do: nil
  defp normalize_execution_mode(_mode, default_mode), do: default_mode

  defp normalize_workspace_root_input(workspace_root, fallback) when is_binary(workspace_root) do
    workspace_root
    |> String.trim()
    |> case do
      "" -> normalize_workspace_root_fallback(fallback)
      normalized_workspace_root -> normalized_workspace_root
    end
  end

  defp normalize_workspace_root_input(_workspace_root, fallback),
    do: normalize_workspace_root_fallback(fallback)

  defp normalize_workspace_root_fallback(fallback) when is_binary(fallback) do
    fallback
    |> String.trim()
    |> case do
      "" -> ""
      normalized_workspace_root -> normalized_workspace_root
    end
  end

  defp normalize_workspace_root_fallback(_fallback), do: ""

  defp normalize_optional_workspace_root(workspace_root) when is_binary(workspace_root) do
    workspace_root
    |> String.trim()
    |> case do
      "" -> nil
      normalized_workspace_root -> normalized_workspace_root
    end
  end

  defp normalize_optional_workspace_root(_workspace_root), do: nil

  defp maybe_put_environment_field(environment_state, _key, nil), do: environment_state

  defp maybe_put_environment_field(environment_state, key, value),
    do: Map.put(environment_state, key, value)

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

  defp resolve_provider_credential_report(onboarding_step, onboarding_state) do
    if onboarding_step == 3 do
      onboarding_state
      |> fetch_step_state(3)
      |> Map.get("provider_credentials")
      |> ProviderCredentialChecks.run()
    else
      nil
    end
  end

  defp resolve_github_credential_report(onboarding_step, onboarding_state) do
    if onboarding_step == 4 do
      owner_context = resolve_owner_context(onboarding_state)

      onboarding_state
      |> fetch_step_state(4)
      |> Map.get("github_credentials")
      |> GitHubCredentialChecks.run(owner_context)
    else
      nil
    end
  end

  defp resolve_webhook_simulation_report(onboarding_step, onboarding_state) do
    if onboarding_step == 6 do
      onboarding_state
      |> fetch_step_state(6)
      |> Map.get("webhook_simulation")
      |> WebhookSimulationChecks.run()
    else
      nil
    end
  end

  defp resolve_environment_defaults_report(
         onboarding_step,
         onboarding_state,
         default_environment,
         workspace_root
       ) do
    if onboarding_step == 5 do
      persisted_environment_state =
        onboarding_state
        |> fetch_step_state(5)
        |> Map.get("environment_defaults", %{})
        |> normalize_environment_state()

      EnvironmentDefaults.run(
        environment_selection(
          %{
            "execution_mode" =>
              Map.get(
                persisted_environment_state,
                :mode,
                default_environment_mode(default_environment)
              ),
            "workspace_root" => Map.get(persisted_environment_state, :workspace_root, workspace_root || "")
          },
          default_environment,
          workspace_root
        )
      )
    else
      nil
    end
  end

  defp resolve_owner_context(onboarding_state) do
    onboarding_state
    |> fetch_step_state(2)
    |> Map.get("owner_email")
    |> normalize_owner_context()
  end

  defp normalize_owner_context(owner_context) when is_binary(owner_context) do
    owner_context
    |> String.trim()
    |> case do
      "" -> nil
      normalized_owner_context -> normalized_owner_context
    end
  end

  defp normalize_owner_context(_owner_context), do: nil

  defp save_step_progress(socket, validated_note, step_params) do
    case socket.assigns.onboarding_step do
      1 ->
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

      3 ->
        provider_credential_report =
          socket.assigns.onboarding_state
          |> fetch_step_state(3)
          |> Map.get("provider_credentials")
          |> ProviderCredentialChecks.run()

        socket = assign(socket, :provider_credential_report, provider_credential_report)

        if ProviderCredentialChecks.blocked?(provider_credential_report) do
          {:noreply, assign(socket, :save_error, provider_block_message(provider_credential_report))}
        else
          persist_step_progress(socket, %{
            "validated_note" => validated_note,
            "provider_credentials" => ProviderCredentialChecks.serialize_for_state(provider_credential_report)
          })
        end

      4 ->
        github_credential_report =
          socket.assigns.onboarding_state
          |> fetch_step_state(4)
          |> Map.get("github_credentials")
          |> GitHubCredentialChecks.run(resolve_owner_context(socket.assigns.onboarding_state))

        socket = assign(socket, :github_credential_report, github_credential_report)

        if GitHubCredentialChecks.blocked?(github_credential_report) do
          {:noreply, assign(socket, :save_error, github_block_message(github_credential_report))}
        else
          persist_step_progress(socket, %{
            "validated_note" => validated_note,
            "github_credentials" => GitHubCredentialChecks.serialize_for_state(github_credential_report)
          })
        end

      5 ->
        environment_defaults_report =
          step_params
          |> environment_selection(
            socket.assigns.default_environment,
            socket.assigns.workspace_root
          )
          |> EnvironmentDefaults.run()

        socket =
          socket
          |> assign(:environment_defaults_report, environment_defaults_report)
          |> assign_step_form(
            socket.assigns.onboarding_step,
            socket.assigns.onboarding_state,
            socket.assigns.default_environment,
            socket.assigns.workspace_root,
            %{
              "validated_note" => validated_note,
              "execution_mode" => mode_param(environment_defaults_report.mode),
              "workspace_root" => environment_defaults_report.workspace_root || ""
            }
          )

        if EnvironmentDefaults.blocked?(environment_defaults_report) do
          {:noreply, assign(socket, :save_error, environment_block_message(environment_defaults_report))}
        else
          persist_step_progress(
            socket,
            %{
              "validated_note" => validated_note,
              "environment_defaults" => EnvironmentDefaults.serialize_for_state(environment_defaults_report)
            },
            EnvironmentDefaults.system_config_updates(environment_defaults_report)
          )
        end

      6 ->
        webhook_simulation_report =
          socket.assigns.onboarding_state
          |> fetch_step_state(6)
          |> Map.get("webhook_simulation")
          |> WebhookSimulationChecks.run()

        socket = assign(socket, :webhook_simulation_report, webhook_simulation_report)

        if WebhookSimulationChecks.blocked?(webhook_simulation_report) do
          {:noreply,
           assign(
             socket,
             :save_error,
             webhook_simulation_block_message(webhook_simulation_report)
           )}
        else
          persist_step_progress(socket, %{
            "validated_note" => validated_note,
            "webhook_simulation" => WebhookSimulationChecks.serialize_for_state(webhook_simulation_report),
            "issue_bot_defaults" => WebhookSimulationChecks.issue_bot_defaults(webhook_simulation_report)
          })
        end

      _step ->
        persist_step_progress(socket, %{"validated_note" => validated_note})
    end
  end

  defp persist_step_progress(socket, step_state, config_updates \\ %{}) do
    case SystemConfig.save_step_progress(step_state, config_updates) do
      {:ok, %SystemConfig{} = config} ->
        {:noreply,
         socket
         |> assign_config_state(config)
         |> assign(:save_error, nil)
         |> assign_step_form(
           config.onboarding_step,
           config.onboarding_state,
           config.default_environment,
           config.workspace_root
         )}

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

  defp provider_block_message(report) do
    remediation =
      report
      |> ProviderCredentialChecks.blocked_credentials()
      |> Enum.map(fn credential -> "#{credential.name}: #{credential.remediation}" end)
      |> Enum.join(" ")

    String.trim(
      "At least one provider credential must verify as Active before continuing to GitHub setup. No setup progress was saved. #{remediation}"
    )
  end

  defp github_block_message(report) do
    remediation =
      report
      |> GitHubCredentialChecks.blocked_paths()
      |> Enum.map(fn path ->
        typed_error = path.error_type || "github_integration_unknown_error"
        "#{path.name} [#{typed_error}]: #{path.remediation}"
      end)
      |> Enum.join(" ")

    String.trim(
      "GitHub integration validation failed for both GitHub App and PAT fallback. Step 4 remains blocked with typed integration errors. No setup progress was saved. #{remediation}"
    )
  end

  defp environment_block_message(report) do
    remediation =
      report
      |> EnvironmentDefaults.blocked_checks()
      |> Enum.map(fn check -> "#{check.name}: #{check.remediation}" end)
      |> Enum.join(" ")

    String.trim(
      "Environment defaults validation failed. Step 5 remains blocked and no environment defaults were changed. #{remediation}"
    )
  end

  defp webhook_simulation_block_message(report) do
    failure_reason =
      report
      |> WebhookSimulationChecks.failure_reason()
      |> case do
        nil -> "Unknown simulation failure."
        reason -> reason
      end

    String.trim(
      "Webhook simulation failed. Issue Bot defaults remain blocked until signature and routing readiness checks pass. The last failure reason is retained for retry: #{failure_reason}"
    )
  end

  defp prerequisite_status_label(:pass), do: "Pass"
  defp prerequisite_status_label(:timeout), do: "Timeout"
  defp prerequisite_status_label(:fail), do: "Fail"

  defp prerequisite_status_class(:pass), do: "badge-success"
  defp prerequisite_status_class(:timeout), do: "badge-warning"
  defp prerequisite_status_class(:fail), do: "badge-error"

  defp provider_status_label(:active), do: "Active"
  defp provider_status_label(:invalid), do: "Invalid"
  defp provider_status_label(:not_set), do: "Not set"
  defp provider_status_label(:rotating), do: "Rotating"

  defp provider_status_class(:active), do: "badge-success"
  defp provider_status_class(:invalid), do: "badge-error"
  defp provider_status_class(:not_set), do: "badge-warning"
  defp provider_status_class(:rotating), do: "badge-info"

  defp github_status_label(:ready), do: "Ready"
  defp github_status_label(:invalid), do: "Invalid"
  defp github_status_label(:not_configured), do: "Not configured"

  defp github_status_class(:ready), do: "badge-success"
  defp github_status_class(:invalid), do: "badge-error"
  defp github_status_class(:not_configured), do: "badge-warning"

  defp environment_check_status_label(:ready), do: "Ready"
  defp environment_check_status_label(:failed), do: "Failed"

  defp environment_check_status_class(:ready), do: "badge-success"
  defp environment_check_status_class(:failed), do: "badge-error"

  defp environment_mode_label(:cloud), do: "Cloud"
  defp environment_mode_label(:local), do: "Local"

  defp environment_default_label(:sprite), do: "sprite"
  defp environment_default_label(:local), do: "local"

  defp webhook_simulation_status_label(:ready), do: "Ready"
  defp webhook_simulation_status_label(:blocked), do: "Blocked"

  defp webhook_simulation_status_class(:ready), do: "badge-success"
  defp webhook_simulation_status_class(:blocked), do: "badge-error"

  defp webhook_check_status_label(:ready), do: "Ready"
  defp webhook_check_status_label(:failed), do: "Failed"

  defp webhook_check_status_class(:ready), do: "badge-success"
  defp webhook_check_status_class(:failed), do: "badge-error"

  defp issue_bot_default_enabled(issue_bot_defaults) when is_map(issue_bot_defaults) do
    issue_bot_defaults
    |> Map.get("enabled")
    |> case do
      true -> "true"
      false -> "false"
      _other -> "unknown"
    end
  end

  defp issue_bot_default_enabled(_issue_bot_defaults), do: "unknown"

  defp issue_bot_default_approval_mode(issue_bot_defaults) when is_map(issue_bot_defaults) do
    issue_bot_defaults
    |> Map.get("approval_mode")
    |> case do
      value when is_binary(value) and value != "" -> value
      _other -> "unknown"
    end
  end

  defp issue_bot_default_approval_mode(_issue_bot_defaults), do: "unknown"

  defp github_repository_access_label(:confirmed), do: "Confirmed"
  defp github_repository_access_label(:unconfirmed), do: "Unconfirmed"

  defp github_repositories_text(repositories) when is_list(repositories) do
    case repositories do
      [] -> "none reported"
      _repositories -> Enum.join(repositories, ", ")
    end
  end

  defp github_repositories_text(_repositories), do: "none reported"

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
    |> assign(:default_environment, config.default_environment)
    |> assign(:workspace_root, config.workspace_root)
    |> assign(
      :prerequisite_report,
      resolve_prerequisite_report(config.onboarding_step, config.onboarding_state)
    )
    |> assign(
      :provider_credential_report,
      resolve_provider_credential_report(config.onboarding_step, config.onboarding_state)
    )
    |> assign(
      :github_credential_report,
      resolve_github_credential_report(config.onboarding_step, config.onboarding_state)
    )
    |> assign(
      :webhook_simulation_report,
      resolve_webhook_simulation_report(config.onboarding_step, config.onboarding_state)
    )
    |> assign(
      :environment_defaults_report,
      resolve_environment_defaults_report(
        config.onboarding_step,
        config.onboarding_state,
        config.default_environment,
        config.workspace_root
      )
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

  defp provider_dom_id(provider) when is_atom(provider), do: Atom.to_string(provider)
  defp provider_dom_id(provider) when is_binary(provider), do: provider
  defp provider_dom_id(_provider), do: "unknown"

  defp webhook_event_dom_id(event) when is_binary(event) do
    event
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "unknown"
      dom_id -> dom_id
    end
  end

  defp webhook_event_dom_id(event) when is_atom(event) do
    event
    |> Atom.to_string()
    |> webhook_event_dom_id()
  end

  defp webhook_event_dom_id(_event), do: "unknown"

  defp github_path_dom_id(path) when is_atom(path), do: Atom.to_string(path)
  defp github_path_dom_id(path) when is_binary(path), do: path
  defp github_path_dom_id(_path), do: "unknown"
end
