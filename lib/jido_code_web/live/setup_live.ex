defmodule JidoCodeWeb.SetupLive do
  use JidoCodeWeb, :live_view

  require Ash.Query

  alias Ecto.Adapters.SQL
  alias JidoCode.Projects.Project
  alias JidoCode.Setup.{Credential, GithubAppInstallation, SystemConfig}

  @steps [
    %{id: 0, key: :welcome, title: "Welcome & Persistence"},
    %{id: 1, key: :admin_password, title: "Admin Password (Optional)"},
    %{id: 2, key: :llm_providers, title: "LLM Providers"},
    %{id: 3, key: :github_app, title: "GitHub Connection"},
    %{id: 4, key: :environment, title: "Default Environment"},
    %{id: 5, key: :import_project, title: "Import First Project"},
    %{id: 6, key: :complete, title: "Complete Setup"}
  ]

  @last_step_id length(@steps) - 1

  @llm_env_vars %{
    anthropic: "ANTHROPIC_API_KEY",
    openai: "OPENAI_API_KEY",
    google: "GOOGLE_AI_API_KEY"
  }

  @impl true
  def mount(_params, _session, socket) do
    case load_or_create_system_config() do
      {:ok, config} ->
        current_step_id = normalize_step_id(config.onboarding_step)

        socket =
          socket
          |> assign(:steps, @steps)
          |> assign(:last_step_id, @last_step_id)
          |> assign(:system_config, config)
          |> assign(:current_step_id, current_step_id)
          |> assign(:db_status, db_status())
          |> assign(:admin_password_set?, env_present?("JIDO_CODE_ADMIN_PASSWORD"))
          |> assign(:llm_checks, llm_checks())
          |> assign(:github_pat_check, github_pat_check())
          |> assign(:github_app_check, github_app_check())
          |> assign(:environment_check, environment_check(config.local_workspace_root))
          |> assign(:available_repos, [])
          |> assign(:selected_repo_full_name, nil)
          |> assign(:import_result, nil)
          |> assign(:workspace_form, to_form(%{"workspace_root" => config.local_workspace_root}, as: :workspace))
          |> assign(:repo_form, to_form(%{"selected_repo" => ""}, as: :repo))

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Unable to load setup state.")
         |> assign(:steps, @steps)
         |> assign(:last_step_id, @last_step_id)
         |> assign(:current_step_id, 0)
         |> assign(:system_config, nil)
         |> assign(:db_status, %{ok?: false, message: "No setup configuration found."})
         |> assign(:admin_password_set?, false)
         |> assign(:llm_checks, llm_checks())
         |> assign(:github_pat_check, github_pat_check())
         |> assign(:github_app_check, github_app_check())
         |> assign(:environment_check, %{ok?: false, message: "Environment not configured."})
         |> assign(:available_repos, [])
         |> assign(:selected_repo_full_name, nil)
         |> assign(:import_result, nil)
         |> assign(:workspace_form, to_form(%{"workspace_root" => "~/.jido_code/workspaces"}, as: :workspace))
         |> assign(:repo_form, to_form(%{"selected_repo" => ""}, as: :repo))}
    end
  end

  @impl true
  def handle_event("next_step", _params, socket) do
    case validate_step(socket.assigns.current_step_id, socket.assigns) do
      :ok ->
        next_step_id = min(socket.assigns.current_step_id + 1, @last_step_id)
        {:noreply, persist_step(socket, next_step_id)}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def handle_event("back_step", _params, socket) do
    previous_step_id = max(socket.assigns.current_step_id - 1, 0)
    {:noreply, persist_step(socket, previous_step_id)}
  end

  @impl true
  def handle_event("skip_step", _params, socket) do
    if socket.assigns.current_step_id == 1 do
      next_step_id = min(socket.assigns.current_step_id + 1, @last_step_id)
      {:noreply, persist_step(socket, next_step_id)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("test_database", _params, socket) do
    {:noreply, assign(socket, :db_status, db_status())}
  end

  @impl true
  def handle_event("test_llm_provider", %{"provider" => provider}, socket) do
    provider_atom = provider_to_atom(provider)

    check = test_llm_provider(provider_atom)
    _ = persist_provider_credential(provider_atom, check)

    llm_checks = Map.put(socket.assigns.llm_checks, provider_atom, check)
    {:noreply, assign(socket, :llm_checks, llm_checks)}
  end

  @impl true
  def handle_event("test_github_pat", _params, socket) do
    check = test_github_pat()
    _ = persist_provider_credential(:github_pat, check)
    {:noreply, assign(socket, :github_pat_check, check)}
  end

  @impl true
  def handle_event("test_github_app", _params, socket) do
    {check, installations} = test_github_app()
    _ = persist_provider_credential(:github_app, check)
    persist_installations(installations)
    {:noreply, assign(socket, :github_app_check, check)}
  end

  @impl true
  def handle_event("workspace_change", %{"workspace" => %{"workspace_root" => workspace_root}}, socket) do
    workspace_root = String.trim(workspace_root)

    socket =
      socket
      |> assign(:workspace_form, to_form(%{"workspace_root" => workspace_root}, as: :workspace))
      |> update_workspace_root(workspace_root)
      |> assign(:environment_check, environment_check(workspace_root))

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_environment", %{"type" => environment_type}, socket) do
    environment = if environment_type == "sprite", do: :sprite, else: :local

    socket =
      case socket.assigns.system_config do
        nil ->
          socket

        config ->
          case config
               |> Ash.Changeset.for_update(:set_default_environment, %{default_environment: environment})
               |> Ash.update() do
            {:ok, updated_config} ->
              assign(socket, :system_config, updated_config)

            {:error, _reason} ->
              put_flash(socket, :error, "Unable to update default environment.")
          end
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_environment", _params, socket) do
    workspace_root = socket.assigns.workspace_form.params["workspace_root"] || ""
    {:noreply, assign(socket, :environment_check, environment_check(workspace_root))}
  end

  @impl true
  def handle_event("load_repos", _params, socket) do
    {repos, message} = fetch_available_repos(socket.assigns)

    socket =
      socket
      |> assign(:available_repos, repos)
      |> assign(:repo_form, to_form(%{"selected_repo" => ""}, as: :repo))
      |> assign(:selected_repo_full_name, nil)

    socket = put_flash(socket, :info, message)

    {:noreply, socket}
  end

  @impl true
  def handle_event("repo_change", %{"repo" => %{"selected_repo" => selected_repo}}, socket) do
    {:noreply,
     socket
     |> assign(:selected_repo_full_name, selected_repo)
     |> assign(:repo_form, to_form(%{"selected_repo" => selected_repo}, as: :repo))}
  end

  @impl true
  def handle_event("import_repo", _params, socket) do
    selected = socket.assigns.selected_repo_full_name

    with true <- is_binary(selected) and selected != "",
         %{full_name: _full_name} = repo <- Enum.find(socket.assigns.available_repos, &(&1.full_name == selected)),
         {:ok, project} <- create_or_update_project(socket.assigns.system_config, repo),
         {:ok, project, import_message} <- maybe_clone_project(socket.assigns.system_config, project, repo) do
      {:noreply,
       socket
       |> assign(:import_result, %{ok?: true, message: import_message, project_id: project.id})
       |> put_flash(:info, "Project imported: #{repo.full_name}")}
    else
      false ->
        {:noreply, put_flash(socket, :error, "Select a repository before importing.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:import_result, %{ok?: false, message: inspect(reason), project_id: nil})
         |> put_flash(:error, "Import failed: #{format_reason(reason)}")}

      nil ->
        {:noreply, put_flash(socket, :error, "Selected repository is not available.")}
    end
  end

  @impl true
  def handle_event("finish_onboarding", _params, socket) do
    {:noreply, finalize_onboarding(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="setup-wizard" class="mx-auto max-w-5xl rounded-2xl border border-base-300 bg-base-100 p-8 shadow-sm">
        <header class="space-y-4">
          <p class="text-sm font-medium uppercase tracking-[0.2em] text-base-content/50">Onboarding</p>
          <h1 class="text-3xl font-semibold tracking-tight text-base-content">Setup Wizard</h1>

          <div id="setup-progress" class="space-y-2">
            <div class="flex items-center justify-between text-sm text-base-content/60">
              <span>Step {@current_step_id + 1} of {length(@steps)}</span>
              <span>{current_step(@steps, @current_step_id).title}</span>
            </div>
            <progress class="progress progress-primary w-full" value={@current_step_id + 1} max={length(@steps)} />
          </div>
        </header>

        <article id="setup-step-content" class="mt-8 rounded-xl border border-base-300/70 bg-base-50 p-6">
          {step_body(assigns)}
        </article>

        <footer class="mt-8 flex items-center justify-between">
          <button
            id="setup-back-button"
            type="button"
            class="btn btn-ghost"
            phx-click="back_step"
            disabled={@current_step_id == 0}
          >
            Back
          </button>

          <div class="flex items-center gap-3">
            <button
              :if={@current_step_id == 1}
              id="setup-skip-button"
              type="button"
              class="btn btn-outline"
              phx-click="skip_step"
            >
              Skip
            </button>

            <button
              :if={@current_step_id < @last_step_id}
              id="setup-next-button"
              type="button"
              class="btn btn-primary"
              phx-click="next_step"
            >
              Next
            </button>

            <button
              :if={@current_step_id == @last_step_id}
              id="setup-finish-button"
              type="button"
              class="btn btn-success"
              phx-click="finish_onboarding"
            >
              Go to Dashboard
            </button>
          </div>
        </footer>
      </section>
    </Layouts.app>
    """
  end

  defp finalize_onboarding(socket) do
    case socket.assigns.system_config do
      nil ->
        put_flash(socket, :error, "Setup state unavailable.")

      config ->
        handle_complete_onboarding(socket, complete_onboarding(config))
    end
  end

  defp handle_complete_onboarding(socket, {:ok, updated_config}) do
    destination = onboarding_destination(socket.assigns[:current_user])

    socket
    |> assign(:system_config, updated_config)
    |> put_flash(:info, "Setup complete.")
    |> push_navigate(to: destination)
  end

  defp handle_complete_onboarding(socket, {:error, _reason}) do
    put_flash(socket, :error, "Unable to complete setup.")
  end

  defp onboarding_destination(current_user) do
    if current_user, do: ~p"/dashboard", else: ~p"/"
  end

  defp step_body(%{current_step_id: 0} = assigns) do
    ~H"""
    <div id="setup-step-welcome" class="space-y-4">
      <h2 class="text-xl font-semibold text-base-content">Welcome & Persistence</h2>
      <p class="text-base-content/70">Validate the database connection before continuing.</p>

      <div class="flex items-center gap-3">
        <span class={status_class(@db_status.ok?)}>{if @db_status.ok?, do: "Healthy", else: "Not Ready"}</span>
        <span class="text-sm text-base-content/70">{@db_status.message}</span>
      </div>

      <button id="setup-test-db" type="button" class="btn btn-outline" phx-click="test_database">
        Test Database
      </button>
    </div>
    """
  end

  defp step_body(%{current_step_id: 1} = assigns) do
    ~H"""
    <div id="setup-step-admin-password" class="space-y-4">
      <h2 class="text-xl font-semibold text-base-content">Admin Password (Optional)</h2>
      <p class="text-base-content/70">
        If this app is exposed outside localhost, set `JIDO_CODE_ADMIN_PASSWORD`.
      </p>

      <div class="flex items-center gap-3">
        <span class={status_class(@admin_password_set?)}>{if @admin_password_set?, do: "Configured", else: "Not Set"}</span>
        <span class="text-sm text-base-content/70">
          {if @admin_password_set?, do: "Password detected in env.", else: "You can skip and configure later."}
        </span>
      </div>
    </div>
    """
  end

  defp step_body(%{current_step_id: 2} = assigns) do
    ~H"""
    <div id="setup-step-llm-providers" class="space-y-4">
      <h2 class="text-xl font-semibold text-base-content">LLM Providers</h2>
      <p class="text-base-content/70">At least one provider must be detected and tested.</p>

      <div class="space-y-3">
        <%= for provider <- [:anthropic, :openai, :google] do %>
          <% check = @llm_checks[provider] %>
          <div class="flex items-center justify-between rounded-lg border border-base-300 bg-base-100 p-3">
            <div class="space-y-1">
              <p class="font-medium capitalize">{provider}</p>
              <p class="text-sm text-base-content/70">{check.message}</p>
            </div>
            <div class="flex items-center gap-3">
              <span class={status_class(check.detected? && check.ok?)}>
                <%= cond do %>
                  <% check.ok? -> %>
                    Ready
                  <% check.detected? -> %>
                    Detected
                  <% true -> %>
                    Missing
                <% end %>
              </span>
              <button
                id={"setup-test-llm-#{provider}"}
                type="button"
                class="btn btn-outline btn-sm"
                phx-click="test_llm_provider"
                phx-value-provider={provider}
                disabled={!check.detected?}
              >
                Test
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp step_body(%{current_step_id: 3} = assigns) do
    ~H"""
    <div id="setup-step-github" class="space-y-4">
      <h2 class="text-xl font-semibold text-base-content">GitHub Connection</h2>
      <p class="text-base-content/70">Validate either GitHub App or Personal Access Token.</p>

      <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-3">
        <div class="flex items-center justify-between">
          <div>
            <p class="font-medium">GitHub App</p>
            <p class="text-sm text-base-content/70">Uses `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY`</p>
          </div>
          <span class={status_class(@github_app_check.ok?)}>
            {if @github_app_check.ok?,
              do: "Connected",
              else: if(@github_app_check.detected?, do: "Detected", else: "Missing")}
          </span>
        </div>
        <p class="text-sm text-base-content/70">{@github_app_check.message}</p>
        <button
          id="setup-test-github-app"
          type="button"
          class="btn btn-outline btn-sm"
          phx-click="test_github_app"
          disabled={!@github_app_check.detected?}
        >
          Test GitHub App
        </button>
      </div>

      <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-3">
        <div class="flex items-center justify-between">
          <div>
            <p class="font-medium">GitHub PAT</p>
            <p class="text-sm text-base-content/70">Uses `GITHUB_PAT`</p>
          </div>
          <span class={status_class(@github_pat_check.ok?)}>
            {if @github_pat_check.ok?,
              do: "Connected",
              else: if(@github_pat_check.detected?, do: "Detected", else: "Missing")}
          </span>
        </div>
        <p class="text-sm text-base-content/70">{@github_pat_check.message}</p>
        <button
          id="setup-test-github-pat"
          type="button"
          class="btn btn-outline btn-sm"
          phx-click="test_github_pat"
          disabled={!@github_pat_check.detected?}
        >
          Test GitHub PAT
        </button>
      </div>
    </div>
    """
  end

  defp step_body(%{current_step_id: 4} = assigns) do
    ~H"""
    <div id="setup-step-environment" class="space-y-4">
      <h2 class="text-xl font-semibold text-base-content">Default Environment</h2>
      <p class="text-base-content/70">Set environment and validate local workspace prerequisites.</p>

      <div class="flex flex-wrap gap-3">
        <button
          id="setup-environment-local"
          type="button"
          class={[
            "btn",
            if(@system_config && @system_config.default_environment == :local,
              do: "btn-primary",
              else: "btn-outline"
            )
          ]}
          phx-click="set_environment"
          phx-value-type="local"
        >
          Local
        </button>

        <button
          id="setup-environment-sprite"
          type="button"
          class={[
            "btn",
            if(@system_config && @system_config.default_environment == :sprite,
              do: "btn-primary",
              else: "btn-outline"
            )
          ]}
          phx-click="set_environment"
          phx-value-type="sprite"
        >
          Sprite
        </button>
      </div>

      <.form for={@workspace_form} id="setup-workspace-form" phx-change="workspace_change" class="space-y-2">
        <.input field={@workspace_form[:workspace_root]} type="text" label="Workspace Root" />
      </.form>

      <div class="text-sm text-base-content/70 space-y-1">
        <p>git: {if @environment_check.git_available?, do: "available", else: "missing"}</p>
        <p>claude: {if @environment_check.claude_available?, do: "available", else: "not found (non-blocking)"}</p>
        <p>writable path: {if @environment_check.path_writable?, do: "yes", else: "no"}</p>
      </div>

      <div class="flex items-center gap-3">
        <span class={status_class(@environment_check.ok?)}>
          {if @environment_check.ok?, do: "Ready", else: "Needs Fixes"}
        </span>
        <span class="text-sm text-base-content/70">{@environment_check.message}</span>
      </div>

      <button id="setup-validate-environment" type="button" class="btn btn-outline" phx-click="validate_environment">
        Re-check Environment
      </button>
    </div>
    """
  end

  defp step_body(%{current_step_id: 5} = assigns) do
    ~H"""
    <div id="setup-step-import-project" class="space-y-4">
      <h2 class="text-xl font-semibold text-base-content">Import First Project</h2>
      <p class="text-base-content/70">Load repositories from your connected GitHub credentials.</p>

      <div class="flex gap-3">
        <button id="setup-load-repos" type="button" class="btn btn-outline" phx-click="load_repos">
          Load Repositories
        </button>
      </div>

      <.form for={@repo_form} id="setup-repo-form" phx-change="repo_change" class="space-y-2">
        <.input
          field={@repo_form[:selected_repo]}
          type="select"
          label="Repository"
          options={repo_options(@available_repos)}
          prompt="Select repository"
        />
      </.form>

      <button id="setup-import-repo" type="button" class="btn btn-primary" phx-click="import_repo">
        Import Selected Repository
      </button>

      <%= if @import_result do %>
        <div class={[
          "rounded-lg border p-3 text-sm",
          @import_result.ok? && "border-success/40 bg-success/10 text-success",
          !@import_result.ok? && "border-error/40 bg-error/10 text-error"
        ]}>
          {@import_result.message}
        </div>
      <% end %>
    </div>
    """
  end

  defp step_body(%{current_step_id: 6} = assigns) do
    ~H"""
    <div id="setup-step-complete" class="space-y-3">
      <h2 class="text-xl font-semibold text-base-content">Complete Setup</h2>
      <p class="text-base-content/70">
        Finalize onboarding and unlock dashboard/routes.
      </p>
    </div>
    """
  end

  defp current_step(steps, current_step_id), do: Enum.at(steps, current_step_id)
  defp normalize_step_id(step_id) when is_integer(step_id), do: min(max(step_id, 0), @last_step_id)
  defp normalize_step_id(_step_id), do: 0

  defp status_class(true), do: "badge badge-success"
  defp status_class(false), do: "badge badge-error"

  defp validate_step(0, %{db_status: %{ok?: true}}), do: :ok

  defp validate_step(0, _assigns),
    do: {:error, "Step 1 requires a successful database health check."}

  defp validate_step(1, _assigns), do: :ok

  defp validate_step(2, %{llm_checks: checks}) do
    if Enum.any?(checks, fn {_provider, check} -> check.ok? end) do
      :ok
    else
      {:error, "Step 3 requires at least one LLM provider connection test to pass."}
    end
  end

  defp validate_step(3, %{github_pat_check: pat, github_app_check: app}) do
    if pat.ok? || app.ok? do
      :ok
    else
      {:error, "Step 4 requires either GitHub PAT or GitHub App connection test to pass."}
    end
  end

  defp validate_step(4, %{environment_check: %{ok?: true}}), do: :ok

  defp validate_step(4, _assigns),
    do: {:error, "Step 5 requires a writable workspace path and git on PATH."}

  defp validate_step(5, %{import_result: %{ok?: true}}), do: :ok

  defp validate_step(5, _assigns),
    do: {:error, "Step 6 requires importing at least one project."}

  defp validate_step(6, _assigns), do: :ok

  defp persist_step(socket, step_id) do
    case socket.assigns.system_config do
      nil ->
        assign(socket, :current_step_id, step_id)

      config ->
        case config
             |> Ash.Changeset.for_update(:set_onboarding_step, %{onboarding_step: step_id})
             |> Ash.update(action: :set_onboarding_step) do
          {:ok, updated_config} ->
            socket
            |> assign(:system_config, updated_config)
            |> assign(:current_step_id, step_id)

          {:error, _reason} ->
            socket
            |> put_flash(:error, "Unable to save setup progress.")
            |> assign(:current_step_id, step_id)
        end
    end
  end

  defp load_or_create_system_config do
    SystemConfig
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.Query.limit(1)
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> SystemConfig.create(%{})
      {:ok, config} -> {:ok, config}
      {:error, reason} -> {:error, reason}
    end
  end

  defp complete_onboarding(config) do
    with {:ok, config} <-
           config
           |> Ash.Changeset.for_update(:set_onboarding_step, %{onboarding_step: @last_step_id})
           |> Ash.update(action: :set_onboarding_step) do
      config
      |> Ash.Changeset.for_update(:complete_onboarding, %{})
      |> Ash.update()
    end
  end

  defp db_status do
    case SQL.query(JidoCode.Repo, "SELECT 1", []) do
      {:ok, _result} -> %{ok?: true, message: "Database connection is healthy."}
      {:error, reason} -> %{ok?: false, message: "Database check failed: #{format_reason(reason)}"}
    end
  end

  defp llm_checks do
    Enum.into(@llm_env_vars, %{}, fn {provider, env_var} ->
      detected? = env_present?(env_var)

      {provider,
       %{
         provider: provider,
         env_var: env_var,
         detected?: detected?,
         ok?: false,
         message: if(detected?, do: "Credential detected. Run test.", else: "Env var not set.")
       }}
    end)
  end

  defp github_pat_check do
    detected? = env_present?("GITHUB_PAT")

    %{
      detected?: detected?,
      ok?: false,
      message: if(detected?, do: "PAT detected. Run test.", else: "GITHUB_PAT is not set.")
    }
  end

  defp github_app_check do
    detected? = env_present?("GITHUB_APP_ID") and env_present?("GITHUB_APP_PRIVATE_KEY")

    %{
      detected?: detected?,
      ok?: false,
      message:
        if(detected?,
          do: "GitHub App credentials detected. Run test.",
          else: "GITHUB_APP_ID or GITHUB_APP_PRIVATE_KEY is missing."
        )
    }
  end

  defp environment_check(workspace_root) do
    workspace_root = normalize_workspace_root(workspace_root)
    path_writable? = workspace_path_writable?(workspace_root)
    git_available? = System.find_executable("git") != nil
    claude_available? = System.find_executable("claude") != nil

    ok? = path_writable? and git_available?

    %{
      ok?: ok?,
      message: environment_message(ok?, claude_available?, path_writable?, git_available?),
      workspace_root: workspace_root,
      path_writable?: path_writable?,
      git_available?: git_available?,
      claude_available?: claude_available?
    }
  end

  defp workspace_path_writable?(workspace_root) do
    case File.mkdir_p(workspace_root) do
      :ok ->
        test_file = Path.join(workspace_root, ".jido_code_write_test")
        write_probe_file?(test_file)

      {:error, _reason} ->
        false
    end
  end

  defp write_probe_file?(test_file) do
    case File.write(test_file, "ok") do
      :ok ->
        _ = File.rm(test_file)
        true

      {:error, _reason} ->
        false
    end
  end

  defp environment_message(ok?, claude_available?, path_writable?, git_available?) do
    cond do
      ok? and claude_available? -> "Environment checks passed."
      ok? -> "Environment checks passed (claude CLI not found)."
      not path_writable? -> "Workspace path is not writable."
      not git_available? -> "git is not available on PATH."
      true -> "Environment checks failed."
    end
  end

  defp test_llm_provider(provider) when provider in [:anthropic, :openai, :google] do
    env_var = Map.fetch!(@llm_env_vars, provider)

    case System.get_env(env_var) do
      nil ->
        %{provider: provider, env_var: env_var, detected?: false, ok?: false, message: "Env var not set."}

      key ->
        do_test_llm_provider(provider, key)
    end
  end

  defp test_llm_provider(_provider), do: %{detected?: false, ok?: false, message: "Unknown provider."}

  defp do_test_llm_provider(:anthropic, api_key) do
    request =
      Req.new(
        method: :post,
        url: "https://api.anthropic.com/v1/messages",
        headers: [
          {"x-api-key", api_key},
          {"anthropic-version", "2023-06-01"}
        ],
        json: %{model: "claude-3-5-haiku-20241022", max_tokens: 1, messages: [%{role: "user", content: "ping"}]},
        receive_timeout: 15_000
      )

    case Req.request(request) do
      {:ok, %{status: status}} when status in 200..299 ->
        %{
          provider: :anthropic,
          env_var: "ANTHROPIC_API_KEY",
          detected?: true,
          ok?: true,
          message: "Connection successful."
        }

      {:ok, %{status: status, body: body}} ->
        %{
          provider: :anthropic,
          env_var: "ANTHROPIC_API_KEY",
          detected?: true,
          ok?: false,
          message: "HTTP #{status}: #{short_error(body)}"
        }

      {:error, reason} ->
        %{
          provider: :anthropic,
          env_var: "ANTHROPIC_API_KEY",
          detected?: true,
          ok?: false,
          message: format_reason(reason)
        }
    end
  end

  defp do_test_llm_provider(:openai, api_key) do
    request =
      Req.new(
        method: :get,
        url: "https://api.openai.com/v1/models",
        auth: {:bearer, api_key},
        receive_timeout: 15_000
      )

    case Req.request(request) do
      {:ok, %{status: status}} when status in 200..299 ->
        %{provider: :openai, env_var: "OPENAI_API_KEY", detected?: true, ok?: true, message: "Connection successful."}

      {:ok, %{status: status, body: body}} ->
        %{
          provider: :openai,
          env_var: "OPENAI_API_KEY",
          detected?: true,
          ok?: false,
          message: "HTTP #{status}: #{short_error(body)}"
        }

      {:error, reason} ->
        %{provider: :openai, env_var: "OPENAI_API_KEY", detected?: true, ok?: false, message: format_reason(reason)}
    end
  end

  defp do_test_llm_provider(:google, api_key) do
    request =
      Req.new(
        method: :get,
        url: "https://generativelanguage.googleapis.com/v1beta/models",
        params: [key: api_key],
        receive_timeout: 15_000
      )

    case Req.request(request) do
      {:ok, %{status: status}} when status in 200..299 ->
        %{
          provider: :google,
          env_var: "GOOGLE_AI_API_KEY",
          detected?: true,
          ok?: true,
          message: "Connection successful."
        }

      {:ok, %{status: status, body: body}} ->
        %{
          provider: :google,
          env_var: "GOOGLE_AI_API_KEY",
          detected?: true,
          ok?: false,
          message: "HTTP #{status}: #{short_error(body)}"
        }

      {:error, reason} ->
        %{provider: :google, env_var: "GOOGLE_AI_API_KEY", detected?: true, ok?: false, message: format_reason(reason)}
    end
  end

  defp test_github_pat do
    case System.get_env("GITHUB_PAT") do
      nil ->
        %{detected?: false, ok?: false, message: "GITHUB_PAT is not set."}

      token ->
        request =
          Req.new(
            method: :get,
            url: "https://api.github.com/user",
            auth: {:bearer, token},
            headers: [{"accept", "application/vnd.github+json"}],
            receive_timeout: 15_000
          )

        case Req.request(request) do
          {:ok, %{status: status, body: %{"login" => login}}} when status in 200..299 ->
            %{detected?: true, ok?: true, message: "Connected as #{login}."}

          {:ok, %{status: status, body: body}} ->
            %{detected?: true, ok?: false, message: "HTTP #{status}: #{short_error(body)}"}

          {:error, reason} ->
            %{detected?: true, ok?: false, message: format_reason(reason)}
        end
    end
  end

  defp test_github_app do
    app_id = System.get_env("GITHUB_APP_ID")
    private_key = System.get_env("GITHUB_APP_PRIVATE_KEY")

    if is_nil(app_id) or is_nil(private_key) do
      {%{detected?: false, ok?: false, message: "GITHUB_APP_ID or GITHUB_APP_PRIVATE_KEY missing."}, []}
    else
      test_github_app_with_credentials(app_id, private_key)
    end
  end

  defp test_github_app_with_credentials(app_id, private_key) do
    case github_app_jwt(app_id, private_key) do
      {:ok, jwt} ->
        test_github_app_with_jwt(jwt)

      {:error, reason} ->
        {%{detected?: true, ok?: false, message: "JWT creation failed: #{format_reason(reason)}"}, []}
    end
  end

  defp test_github_app_with_jwt(jwt) do
    app_request = github_app_request(jwt, "/app")
    installations_request = github_app_request(jwt, "/app/installations")

    case Req.request(app_request) do
      {:ok, %{status: status}} when status in 200..299 ->
        fetch_github_installations(installations_request)

      {:ok, %{status: status, body: body}} ->
        github_app_failure(status, body)

      {:error, reason} ->
        github_app_request_error(reason)
    end
  end

  defp fetch_github_installations(installations_request) do
    case Req.request(installations_request) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        installations = Enum.map(body, &normalize_installation/1)
        {%{detected?: true, ok?: true, message: "GitHub App authenticated successfully."}, installations}

      {:ok, %{status: status, body: body}} ->
        github_app_failure(status, body)

      {:error, reason} ->
        github_app_request_error(reason)
    end
  end

  defp github_app_request(jwt, path) do
    Req.new(
      method: :get,
      url: "https://api.github.com#{path}",
      auth: {:bearer, jwt},
      headers: [{"accept", "application/vnd.github+json"}],
      receive_timeout: 15_000
    )
  end

  defp github_app_failure(status, body) do
    {%{detected?: true, ok?: false, message: "HTTP #{status}: #{short_error(body)}"}, []}
  end

  defp github_app_request_error(reason) do
    {%{detected?: true, ok?: false, message: format_reason(reason)}, []}
  end

  defp fetch_available_repos(assigns) do
    cond do
      assigns.github_pat_check.ok? ->
        case fetch_repos_via_pat(System.get_env("GITHUB_PAT")) do
          {:ok, repos} -> {repos, "Loaded #{length(repos)} repositories via PAT."}
          {:error, reason} -> {[], "Repo load failed: #{format_reason(reason)}"}
        end

      assigns.github_app_check.ok? ->
        case fetch_repos_via_app() do
          {:ok, repos} -> {repos, "Loaded #{length(repos)} repositories via GitHub App."}
          {:error, reason} -> {[], "Repo load failed: #{format_reason(reason)}"}
        end

      true ->
        {[], "Connect GitHub App or PAT first."}
    end
  end

  defp fetch_repos_via_pat(nil), do: {:error, :missing_pat}

  defp fetch_repos_via_pat(token) do
    request =
      Req.new(
        method: :get,
        url: "https://api.github.com/user/repos",
        auth: {:bearer, token},
        headers: [{"accept", "application/vnd.github+json"}],
        params: [per_page: 100, sort: "updated"],
        receive_timeout: 20_000
      )

    case Req.request(request) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_list(body) ->
        {:ok, Enum.map(body, &normalize_repo/1)}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{short_error(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_repos_via_app do
    app_id = System.get_env("GITHUB_APP_ID")
    private_key = System.get_env("GITHUB_APP_PRIVATE_KEY")

    with false <- is_nil(app_id) or is_nil(private_key),
         {:ok, jwt} <- github_app_jwt(app_id, private_key),
         {:ok, installation_id} <- first_installation_id(jwt),
         {:ok, installation_token} <- installation_access_token(jwt, installation_id),
         {:ok, repos} <- fetch_installation_repos(installation_token) do
      {:ok, repos}
    else
      true -> {:error, :missing_github_app_credentials}
      {:error, reason} -> {:error, reason}
    end
  end

  defp first_installation_id(jwt) do
    request =
      Req.new(
        method: :get,
        url: "https://api.github.com/app/installations",
        auth: {:bearer, jwt},
        headers: [{"accept", "application/vnd.github+json"}],
        receive_timeout: 15_000
      )

    case Req.request(request) do
      {:ok, %{status: status, body: [first | _]}} when status in 200..299 ->
        {:ok, first["id"]}

      {:ok, %{status: status, body: []}} when status in 200..299 ->
        {:error, :no_installations}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{short_error(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp installation_access_token(jwt, installation_id) do
    request =
      Req.new(
        method: :post,
        url: "https://api.github.com/app/installations/#{installation_id}/access_tokens",
        auth: {:bearer, jwt},
        headers: [{"accept", "application/vnd.github+json"}],
        json: %{},
        receive_timeout: 15_000
      )

    case Req.request(request) do
      {:ok, %{status: status, body: %{"token" => token}}} when status in 200..299 ->
        {:ok, token}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{short_error(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_installation_repos(token) do
    request =
      Req.new(
        method: :get,
        url: "https://api.github.com/installation/repositories",
        auth: {:bearer, token},
        headers: [{"accept", "application/vnd.github+json"}],
        params: [per_page: 100],
        receive_timeout: 20_000
      )

    case Req.request(request) do
      {:ok, %{status: status, body: %{"repositories" => repos}}} when status in 200..299 ->
        {:ok, Enum.map(repos, &normalize_repo/1)}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{short_error(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_or_update_project(system_config, repo) do
    project =
      Project
      |> Ash.Query.filter(github_full_name == ^repo.full_name)
      |> Ash.read_one!()

    attrs = %{
      name: repo.name,
      github_owner: repo.owner,
      github_repo: repo.name,
      default_branch: repo.default_branch,
      environment_type: system_config.default_environment,
      settings: %{}
    }

    if project do
      project
      |> Ash.Changeset.for_update(:update, attrs)
      |> Ash.update()
    else
      Project
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create()
    end
  end

  defp maybe_clone_project(system_config, project, repo) do
    case system_config.default_environment do
      :sprite ->
        set_project_pending_clone(project)

      _ ->
        clone_local_project(system_config, project, repo)
    end
  end

  defp set_project_pending_clone(project) do
    with {:ok, updated_project} <-
           project
           |> Ash.Changeset.for_update(:set_clone_status, %{clone_status: :pending})
           |> Ash.update(action: :set_clone_status) do
      {:ok, updated_project, "Project registered for sprite environment."}
    end
  end

  defp clone_local_project(system_config, project, repo) do
    workspace_root = normalize_workspace_root(system_config.local_workspace_root)
    local_path = Path.join(workspace_root, repo.full_name)

    File.mkdir_p!(Path.dirname(local_path))

    case clone_repository_if_needed(repo, local_path) do
      {:ok, output} ->
        persist_cloned_project(project, local_path, output)

      {:error, output} ->
        persist_clone_error(project, local_path, output)
    end
  end

  defp clone_repository_if_needed(repo, local_path) when is_binary(local_path) and local_path != "" do
    if File.dir?(local_path) do
      {:ok, "Repository already exists locally."}
    else
      run_clone_command(repo, local_path)
    end
  end

  defp run_clone_command(repo, local_path) do
    args = ["clone", "--depth", "1", "--branch", repo.default_branch, repo.clone_url, local_path]

    case System.cmd("git", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, _code} -> {:error, output}
    end
  end

  defp persist_cloned_project(project, local_path, output) do
    with {:ok, updated_project} <-
           project
           |> Ash.Changeset.for_update(:update, %{
             local_path: local_path,
             clone_status: :ready,
             last_synced_at: DateTime.utc_now()
           })
           |> Ash.update() do
      {:ok, updated_project, "Repository cloned to #{local_path}. #{truncate_output(output)}"}
    end
  end

  defp persist_clone_error(project, local_path, output) do
    case project
         |> Ash.Changeset.for_update(:set_clone_status, %{clone_status: :error, local_path: local_path})
         |> Ash.update(action: :set_clone_status) do
      {:ok, _updated_project} ->
        {:error, "Clone failed: #{truncate_output(output)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_workspace_root(socket, workspace_root) do
    case socket.assigns.system_config do
      nil ->
        socket

      config ->
        case config
             |> Ash.Changeset.for_update(:update, %{local_workspace_root: workspace_root})
             |> Ash.update() do
          {:ok, updated_config} -> assign(socket, :system_config, updated_config)
          {:error, _reason} -> put_flash(socket, :error, "Unable to save workspace root.")
        end
    end
  end

  defp persist_provider_credential(provider, check) do
    env_var = provider_env_var(provider)

    attrs = %{
      provider: provider,
      name: provider_name(provider),
      env_var_name: env_var,
      metadata: %{message: check.message},
      status: credential_status(check),
      verified_at: credential_verified_at(check)
    }

    existing =
      Credential
      |> Ash.Query.filter(provider == ^provider and env_var_name == ^env_var)
      |> Ash.read_one!()

    upsert_credential(existing, attrs)
  end

  defp provider_env_var(:anthropic), do: "ANTHROPIC_API_KEY"
  defp provider_env_var(:openai), do: "OPENAI_API_KEY"
  defp provider_env_var(:google), do: "GOOGLE_AI_API_KEY"
  defp provider_env_var(:github_pat), do: "GITHUB_PAT"
  defp provider_env_var(:github_app), do: "GITHUB_APP_PRIVATE_KEY"

  defp credential_status(%{ok?: true}), do: :active
  defp credential_status(%{detected?: true}), do: :invalid
  defp credential_status(_check), do: :not_set

  defp credential_verified_at(%{ok?: true}), do: DateTime.utc_now()
  defp credential_verified_at(_check), do: nil

  defp upsert_credential(nil, attrs) do
    Credential
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create()
  end

  defp upsert_credential(existing, attrs) do
    existing
    |> Ash.Changeset.for_update(:update, Map.delete(attrs, :provider))
    |> Ash.update()
  end

  defp persist_installations(installations) when is_list(installations) do
    Enum.each(installations, fn installation ->
      existing =
        GithubAppInstallation
        |> Ash.Query.filter(installation_id == ^installation.installation_id)
        |> Ash.read_one!()

      attrs = Map.from_struct(installation)

      if existing do
        existing
        |> Ash.Changeset.for_update(:update, attrs)
        |> Ash.update()
      else
        GithubAppInstallation
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create()
      end
    end)

    :ok
  end

  defp normalize_installation(raw) do
    account = raw["account"] || %{}

    %GithubAppInstallation{
      installation_id: raw["id"],
      account_login: account["login"] || "unknown",
      account_type: account_type(account["type"]),
      repository_selection: repository_selection(raw["repository_selection"]),
      selected_repos: [],
      permissions: raw["permissions"] || %{}
    }
  end

  defp normalize_repo(raw) do
    owner = raw["owner"] || %{}

    %{
      full_name: raw["full_name"],
      owner: owner["login"] || "",
      name: raw["name"] || "",
      default_branch: raw["default_branch"] || "main",
      clone_url: raw["clone_url"] || "",
      ssh_url: raw["ssh_url"] || ""
    }
  end

  defp repo_options(repos) do
    Enum.map(repos, fn repo -> {repo.full_name, repo.full_name} end)
  end

  defp provider_to_atom("anthropic"), do: :anthropic
  defp provider_to_atom("openai"), do: :openai
  defp provider_to_atom("google"), do: :google
  defp provider_to_atom(_), do: :anthropic

  defp provider_name(:anthropic), do: "Anthropic"
  defp provider_name(:openai), do: "OpenAI"
  defp provider_name(:google), do: "Google AI"
  defp provider_name(:github_pat), do: "GitHub PAT"
  defp provider_name(:github_app), do: "GitHub App"

  defp account_type("User"), do: :user
  defp account_type("Organization"), do: :organization
  defp account_type(_), do: :organization

  defp repository_selection("all"), do: :all
  defp repository_selection("selected"), do: :selected
  defp repository_selection(_), do: :all

  defp env_present?(name) when is_binary(name) do
    case System.get_env(name) do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  defp normalize_workspace_root(path) do
    path
    |> to_string()
    |> String.trim()
    |> then(fn
      "" -> "~/.jido_code/workspaces"
      root -> root
    end)
    |> String.replace_prefix("~", System.user_home!())
    |> Path.expand()
  end

  defp github_app_jwt(app_id, private_key) do
    app_id_int =
      case Integer.parse(to_string(app_id)) do
        {int, _} -> int
        :error -> nil
      end

    if is_nil(app_id_int) do
      {:error, :invalid_app_id}
    else
      now = DateTime.utc_now() |> DateTime.to_unix()
      claims = %{"iat" => now - 60, "exp" => now + 600, "iss" => app_id_int}

      pem = private_key |> String.replace("\\n", "\n")

      jwk = JOSE.JWK.from_pem(pem)
      token = jwk |> JOSE.JWT.sign(%{"alg" => "RS256"}, claims) |> JOSE.JWS.compact() |> elem(1)
      {:ok, token}
    end
  rescue
    error -> {:error, error}
  end

  defp short_error(body) when is_map(body), do: inspect(Map.take(body, ["message", "error"]))
  defp short_error(body), do: inspect(body)

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)

  defp truncate_output(output) when is_binary(output) and byte_size(output) > 200,
    do: String.slice(output, 0, 200) <> "..."

  defp truncate_output(output), do: to_string(output || "")
end
