defmodule JidoCodeWeb.SettingsLive do
  use JidoCodeWeb, :live_view

  alias JidoCode.Accounts.SecurityTokens
  alias JidoCode.GitHub.Repo
  alias JidoCode.Security.SecretRefs
  alias JidoCodeWeb.Security.UiRedaction

  @secret_scope_options [
    {"Instance", "instance"},
    {"Project", "project"},
    {"Integration", "integration"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    repos = Repo.read!()

    socket =
      socket
      |> assign(:show_add_modal, false)
      |> assign(:form, nil)
      |> assign(:security_tokens, [])
      |> assign(:security_api_keys, [])
      |> assign(:security_audit_events, [])
      |> assign(:security_revocation_error, nil)
      |> assign(:security_status_error, nil)
      |> assign(:security_secret_refs, [])
      |> assign(:security_secret_error, nil)
      |> assign(:security_secret_form, empty_security_secret_form())
      |> assign(:secret_scope_options, @secret_scope_options)
      |> stream(:repos, repos)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = Map.get(params, "tab", "github")

    socket =
      socket
      |> assign(:active_tab, tab)
      |> maybe_load_security_tab(tab)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <div class="max-w-6xl mx-auto py-8">
        <h1 class="text-2xl font-bold mb-6">Settings</h1>

        <div class="flex gap-8">
          <nav class="w-48 shrink-0">
            <ul class="space-y-1">
              <li>
                <.link
                  patch={~p"/settings/github"}
                  class={[
                    "block px-4 py-2 rounded-lg transition-colors text-base-content",
                    @active_tab == "github" && "bg-primary text-primary-content font-medium",
                    @active_tab != "github" && "hover:bg-base-200"
                  ]}
                >
                  <.icon name="hero-code-bracket" class="w-5 h-5 inline-block mr-2" /> GitHub
                </.link>
              </li>
              <li>
                <.link
                  patch={~p"/settings/agents"}
                  class={[
                    "block px-4 py-2 rounded-lg transition-colors text-base-content",
                    @active_tab == "agents" && "bg-primary text-primary-content font-medium",
                    @active_tab != "agents" && "hover:bg-base-200"
                  ]}
                >
                  <.icon name="hero-cpu-chip" class="w-5 h-5 inline-block mr-2" /> Agents
                </.link>
              </li>
              <li>
                <.link
                  patch={~p"/settings/account"}
                  class={[
                    "block px-4 py-2 rounded-lg transition-colors text-base-content",
                    @active_tab == "account" && "bg-primary text-primary-content font-medium",
                    @active_tab != "account" && "hover:bg-base-200"
                  ]}
                >
                  <.icon name="hero-user-circle" class="w-5 h-5 inline-block mr-2" /> Account
                </.link>
              </li>
              <li>
                <.link
                  patch={~p"/settings/security"}
                  class={[
                    "block px-4 py-2 rounded-lg transition-colors text-base-content",
                    @active_tab == "security" && "bg-primary text-primary-content font-medium",
                    @active_tab != "security" && "hover:bg-base-200"
                  ]}
                >
                  <.icon name="hero-shield-check" class="w-5 h-5 inline-block mr-2" /> Security
                </.link>
              </li>
            </ul>
          </nav>

          <div class="flex-1">
            <%= case @active_tab do %>
              <% "github" -> %>
                <.github_tab repos={@streams.repos} show_add_modal={@show_add_modal} form={@form} />
              <% "agents" -> %>
                <.agents_tab />
              <% "account" -> %>
                <.account_tab />
              <% "security" -> %>
                <.security_tab
                  security_tokens={@security_tokens}
                  security_api_keys={@security_api_keys}
                  security_audit_events={@security_audit_events}
                  security_revocation_error={@security_revocation_error}
                  security_status_error={@security_status_error}
                  security_secret_refs={@security_secret_refs}
                  security_secret_error={@security_secret_error}
                  security_secret_form={@security_secret_form}
                  secret_scope_options={@secret_scope_options}
                />
              <% _ -> %>
                <.github_tab repos={@streams.repos} show_add_modal={@show_add_modal} form={@form} />
            <% end %>
          </div>
        </div>
      </div>

      <.modal
        :if={@show_add_modal}
        id="add-repo-modal"
        title="Add GitHub Repository"
        show
        on_cancel={JS.push("close_add_modal")}
      >
        <.form for={@form} phx-change="validate" phx-submit="save_repo" class="space-y-4">
          <.text_field
            field={@form[:owner]}
            label="Owner"
            placeholder="e.g., agentjido"
          />
          <.text_field
            field={@form[:name]}
            label="Repository Name"
            placeholder="e.g., jido"
          />
          <p class="text-sm text-base-content/60">
            Webhook secrets are managed in Security settings via encrypted SecretRef entries.
          </p>
          <div class="flex justify-end gap-3 mt-6">
            <.button type="button" variant="outline" phx-click="close_add_modal">
              Cancel
            </.button>
            <.button type="submit" color="primary">
              Add Repository
            </.button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  defp github_tab(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-6">
        <div>
          <h2 class="text-xl font-semibold">GitHub Repositories</h2>
          <p class="text-sm text-base-content/70 mt-1">
            Manage repositories connected to your agent workflows
          </p>
        </div>
        <button
          type="button"
          phx-click="open_add_modal"
          class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
        >
          <.icon name="hero-plus" class="w-4 h-4 mr-1 inline" /> Add Repository
        </button>
      </div>

      <div class="space-y-4" id="repos-list" phx-update="stream">
        <.card :for={{dom_id, repo} <- @repos} id={dom_id} padding="medium" rounded="large">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <.icon name="hero-folder" class="w-6 h-6 text-base-content/50" />
              <div>
                <p class="font-medium">{repo.full_name}</p>
                <% settings_summary = repo_settings_summary(repo.settings) %>
                <p id={"settings-github-repo-settings-#{repo.id}"} class="text-sm text-base-content/60">
                  {settings_summary.text}
                </p>
                <p
                  :if={settings_summary.security_alert?}
                  id={"settings-github-repo-security-alert-#{repo.id}"}
                  class="text-xs text-warning mt-1"
                >
                  {settings_summary.alert_message}
                </p>
              </div>
            </div>

            <div class="flex items-center gap-4">
              <.toggle_field
                id={"repo-toggle-#{repo.id}"}
                name={"repo-enabled-#{repo.id}"}
                checked={repo.enabled}
                phx-click="toggle_repo"
                phx-value-id={repo.id}
                color="success"
                label={if repo.enabled, do: "Enabled", else: "Disabled"}
              />
              <.button
                variant="outline"
                color="danger"
                size="small"
                phx-click="delete_repo"
                phx-value-id={repo.id}
                data-confirm="Are you sure you want to remove this repository?"
              >
                <.icon name="hero-trash" class="w-4 h-4" />
              </.button>
            </div>
          </div>
        </.card>

        <.card :if={Enum.empty?(Map.values(@repos))} padding="large" rounded="large" class="text-center">
          <.icon name="hero-inbox" class="w-12 h-12 mx-auto text-base-content/30 mb-3" />
          <p class="text-base-content/70">No repositories configured yet.</p>
          <p class="text-sm text-base-content/50 mt-1">
            Click "Add Repository" to connect your first GitHub repo.
          </p>
        </.card>
      </div>
    </div>
    """
  end

  defp agents_tab(assigns) do
    ~H"""
    <div>
      <div class="mb-6">
        <h2 class="text-xl font-semibold">Agent Configuration</h2>
        <p class="text-sm text-base-content/70 mt-1">
          Configure AI agents and their behaviors
        </p>
      </div>

      <.card padding="large" rounded="large" class="text-center">
        <.icon name="hero-cpu-chip" class="w-12 h-12 mx-auto text-base-content/30 mb-3" />
        <p class="text-base-content/70">Agent settings coming soon.</p>
        <p class="text-sm text-base-content/50 mt-1">
          This section will allow you to configure agent behaviors and preferences.
        </p>
      </.card>
    </div>
    """
  end

  defp account_tab(assigns) do
    ~H"""
    <div>
      <div class="mb-6">
        <h2 class="text-xl font-semibold">Account Settings</h2>
        <p class="text-sm text-base-content/70 mt-1">
          Manage your account and preferences
        </p>
      </div>

      <.card padding="large" rounded="large" class="text-center">
        <.icon name="hero-user-circle" class="w-12 h-12 mx-auto text-base-content/30 mb-3" />
        <p class="text-base-content/70">Account settings coming soon.</p>
        <p class="text-sm text-base-content/50 mt-1">
          This section will allow you to manage your profile and account preferences.
        </p>
      </.card>
    </div>
    """
  end

  defp security_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h2 class="text-xl font-semibold">Security Controls</h2>
        <p class="text-sm text-base-content/70 mt-1">
          Review token/key expiry, revoke compromised credentials, and capture revocation audit timestamps.
        </p>
      </div>

      <.card
        :if={@security_status_error}
        id="settings-security-status-error"
        padding="medium"
        rounded="large"
        class="border border-warning/50 bg-warning/10"
      >
        <p id="settings-security-status-error-type" class="text-sm font-medium">
          Typed error: {@security_status_error.error_type}
        </p>
        <p id="settings-security-status-error-message" class="text-sm mt-1">
          {@security_status_error.message}
        </p>
        <p id="settings-security-status-error-recovery" class="text-sm mt-1">
          {@security_status_error.recovery_instruction}
        </p>
      </.card>

      <.card
        :if={@security_revocation_error}
        id="settings-security-revocation-error"
        padding="medium"
        rounded="large"
        class="border border-warning/50 bg-warning/10"
      >
        <p id="settings-security-revocation-error-type" class="text-sm font-medium">
          Typed error: {@security_revocation_error.error_type}
        </p>
        <p id="settings-security-revocation-error-message" class="text-sm mt-1">
          {@security_revocation_error.message}
        </p>
        <p id="settings-security-revocation-recovery" class="text-sm mt-1">
          {@security_revocation_error.recovery_instruction}
        </p>
      </.card>

      <.card id="settings-security-secret-refs" padding="medium" rounded="large">
        <div class="space-y-4">
          <div>
            <h3 class="text-lg font-semibold">Operational Secret References</h3>
            <p class="text-sm text-base-content/70">
              Persist operational values as encrypted SecretRef ciphertext while keeping metadata queryable.
            </p>
          </div>

          <.card
            :if={@security_secret_error}
            id="settings-security-secret-error"
            padding="medium"
            rounded="large"
            class="border border-warning/50 bg-warning/10"
          >
            <p id="settings-security-secret-error-type" class="text-sm font-medium">
              Typed error: {@security_secret_error.error_type}
            </p>
            <p id="settings-security-secret-error-message" class="text-sm mt-1">
              {@security_secret_error.message}
            </p>
            <p id="settings-security-secret-error-recovery" class="text-sm mt-1">
              {@security_secret_error.recovery_instruction}
            </p>
          </.card>

          <.form
            id="settings-security-secret-form"
            for={@security_secret_form}
            phx-submit="save_security_secret_ref"
            class="grid gap-4 md:grid-cols-2"
          >
            <.input
              id="settings-security-secret-scope"
              field={@security_secret_form[:scope]}
              type="select"
              options={@secret_scope_options}
              label="Scope"
            />
            <.input
              id="settings-security-secret-name"
              field={@security_secret_form[:name]}
              type="text"
              label="Name"
              placeholder="github/webhook_secret"
            />
            <.input
              id="settings-security-secret-value"
              field={@security_secret_form[:value]}
              type="password"
              label="Secret Value"
              placeholder="Never shown after save"
            />

            <div class="md:col-span-2">
              <.button id="settings-security-secret-save" type="submit" color="primary">
                Save SecretRef
              </.button>
            </div>
          </.form>

          <div id="settings-security-secret-metadata" class="space-y-3">
            <.card
              :if={Enum.empty?(@security_secret_refs)}
              id="settings-security-secret-empty"
              padding="medium"
              rounded="large"
            >
              No SecretRef metadata stored yet.
            </.card>

            <.card
              :for={secret <- @security_secret_refs}
              id={"settings-security-secret-#{secret.id}"}
              padding="medium"
              rounded="large"
            >
              <dl class="grid grid-cols-1 gap-2 sm:grid-cols-2">
                <div>
                  <dt class="text-xs uppercase text-base-content/60">Scope</dt>
                  <dd id={"settings-security-secret-scope-value-#{secret.id}"} class="font-medium">
                    {secret.scope}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs uppercase text-base-content/60">Name</dt>
                  <dd id={"settings-security-secret-name-value-#{secret.id}"} class="font-medium">
                    {secret.name}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs uppercase text-base-content/60">Source</dt>
                  <dd id={"settings-security-secret-source-value-#{secret.id}"} class="font-medium">
                    {secret.source}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs uppercase text-base-content/60">Key Version</dt>
                  <dd id={"settings-security-secret-key-version-#{secret.id}"} class="font-medium">
                    {secret.key_version}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs uppercase text-base-content/60">Last Rotated At</dt>
                  <dd id={"settings-security-secret-rotated-at-#{secret.id}"} class="font-medium">
                    {format_security_datetime(secret.last_rotated_at)}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs uppercase text-base-content/60">Expires At</dt>
                  <dd id={"settings-security-secret-expires-at-#{secret.id}"} class="font-medium">
                    {format_optional_security_datetime(secret.expires_at)}
                  </dd>
                </div>
              </dl>
            </.card>
          </div>
        </div>
      </.card>

      <div id="settings-security-token-status" class="space-y-3">
        <h3 class="text-lg font-semibold">Session Tokens</h3>

        <.card
          :if={Enum.empty?(@security_tokens)}
          id="settings-security-token-empty"
          padding="medium"
          rounded="large"
        >
          No owner session tokens found.
        </.card>

        <.card
          :for={token <- @security_tokens}
          id={"settings-security-token-#{token.id}"}
          padding="medium"
          rounded="large"
        >
          <div class="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
            <dl class="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <div>
                <dt class="text-xs uppercase text-base-content/60">Status</dt>
                <dd id={"settings-security-token-status-#{token.id}"} class="font-medium">
                  {security_status_label(token.status)}
                </dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">Purpose</dt>
                <dd id={"settings-security-token-purpose-#{token.id}"} class="font-medium">
                  {token.purpose}
                </dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">Expires At</dt>
                <dd id={"settings-security-token-expires-at-#{token.id}"} class="font-medium">
                  {format_security_datetime(token.expires_at)}
                </dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">Revoked At</dt>
                <dd id={"settings-security-token-revoked-at-#{token.id}"} class="font-medium">
                  {format_security_datetime(token.revoked_at)}
                </dd>
              </div>
            </dl>

            <.button
              id={"settings-security-revoke-token-#{token.id}"}
              type="button"
              variant="outline"
              color="danger"
              phx-click="revoke_security_token"
              phx-value-jti={token.id}
            >
              Revoke token
            </.button>
          </div>
        </.card>
      </div>

      <div id="settings-security-api-key-status" class="space-y-3">
        <h3 class="text-lg font-semibold">API Keys</h3>

        <.card
          :if={Enum.empty?(@security_api_keys)}
          id="settings-security-api-key-empty"
          padding="medium"
          rounded="large"
        >
          No owner API keys found.
        </.card>

        <.card
          :for={api_key <- @security_api_keys}
          id={"settings-security-api-key-#{api_key.id}"}
          padding="medium"
          rounded="large"
        >
          <div class="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
            <dl class="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <div>
                <dt class="text-xs uppercase text-base-content/60">Status</dt>
                <dd id={"settings-security-api-key-status-#{api_key.id}"} class="font-medium">
                  {security_status_label(api_key.status)}
                </dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">ID</dt>
                <dd id={"settings-security-api-key-id-#{api_key.id}"} class="font-medium">
                  {api_key.id}
                </dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">Expires At</dt>
                <dd id={"settings-security-api-key-expires-at-#{api_key.id}"} class="font-medium">
                  {format_security_datetime(api_key.expires_at)}
                </dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">Revoked At</dt>
                <dd id={"settings-security-api-key-revoked-at-#{api_key.id}"} class="font-medium">
                  {format_security_datetime(api_key.revoked_at)}
                </dd>
              </div>
            </dl>

            <.button
              id={"settings-security-revoke-api-key-#{api_key.id}"}
              type="button"
              variant="outline"
              color="danger"
              phx-click="revoke_security_api_key"
              phx-value-id={api_key.id}
            >
              Revoke API key
            </.button>
          </div>
        </.card>
      </div>

      <.card id="settings-security-audit-log" padding="medium" rounded="large">
        <h3 class="text-lg font-semibold mb-3">Revocation Audit</h3>
        <ul class="space-y-2">
          <li
            :for={audit <- @security_audit_events}
            id={"settings-security-audit-entry-#{audit.event_id}"}
            class="text-sm"
          >
            {security_audit_message(audit)}
          </li>
        </ul>
        <p :if={Enum.empty?(@security_audit_events)} class="text-sm text-base-content/60">
          No revocation events recorded in this browser session.
        </p>
      </.card>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_repo", %{"id" => id}, socket) do
    repo = Repo.get_by_id!(id)

    result =
      if repo.enabled do
        Repo.disable(repo)
      else
        Repo.enable(repo)
      end

    case result do
      {:ok, updated_repo} ->
        {:noreply, stream_insert(socket, :repos, updated_repo)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update repository")}
    end
  end

  def handle_event("delete_repo", %{"id" => id}, socket) do
    repo = Repo.get_by_id!(id)

    case Ash.destroy(repo) do
      :ok ->
        {:noreply, stream_delete(socket, :repos, repo)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete repository")}
    end
  end

  def handle_event("open_add_modal", _params, socket) do
    form =
      Repo
      |> AshPhoenix.Form.for_create(:create)
      |> to_form()

    {:noreply, assign(socket, show_add_modal: true, form: form)}
  end

  def handle_event("close_add_modal", _params, socket) do
    {:noreply, assign(socket, show_add_modal: false, form: nil)}
  end

  def handle_event("validate", %{"form" => params}, socket) do
    form =
      socket.assigns.form.source
      |> AshPhoenix.Form.validate(params)
      |> to_form()

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save_repo", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, repo} ->
        socket =
          socket
          |> stream_insert(:repos, repo)
          |> assign(show_add_modal: false, form: nil)
          |> put_flash(:info, "Repository added successfully")

        {:noreply, socket}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  def handle_event("save_security_secret_ref", %{"security_secret" => params}, socket) do
    case SecretRefs.persist_operational_secret(params) do
      {:ok, _secret_metadata} ->
        socket =
          socket
          |> assign(:security_secret_error, nil)
          |> assign(:security_secret_form, empty_security_secret_form())
          |> load_security_secret_metadata()
          |> put_flash(:info, "SecretRef saved.")

        {:noreply, socket}

      {:error, typed_error} ->
        socket =
          socket
          |> assign(:security_secret_error, typed_error)
          |> assign(
            :security_secret_form,
            empty_security_secret_form(%{
              "scope" => Map.get(params, "scope", "integration"),
              "name" => Map.get(params, "name", ""),
              "value" => ""
            })
          )

        {:noreply, socket}
    end
  end

  def handle_event("revoke_security_token", %{"jti" => jti}, socket) do
    owner_id = current_owner_id(socket)

    case SecurityTokens.revoke_owner_token(owner_id, jti) do
      {:ok, audit_entry} ->
        socket =
          socket
          |> assign(:security_revocation_error, nil)
          |> prepend_security_audit_event(audit_entry)
          |> load_security_status()
          |> put_flash(:info, "Token revoked.")

        {:noreply, socket}

      {:error, typed_error} ->
        {:noreply, assign(socket, :security_revocation_error, typed_error)}
    end
  end

  def handle_event("revoke_security_api_key", %{"id" => api_key_id}, socket) do
    owner_id = current_owner_id(socket)

    case SecurityTokens.revoke_owner_api_key(owner_id, api_key_id) do
      {:ok, audit_entry} ->
        socket =
          socket
          |> assign(:security_revocation_error, nil)
          |> prepend_security_audit_event(audit_entry)
          |> load_security_status()
          |> put_flash(:info, "API key revoked.")

        {:noreply, socket}

      {:error, typed_error} ->
        {:noreply, assign(socket, :security_revocation_error, typed_error)}
    end
  end

  defp maybe_load_security_tab(socket, "security") do
    socket
    |> load_security_status()
    |> load_security_secret_metadata()
  end

  defp maybe_load_security_tab(socket, _tab), do: socket

  defp load_security_status(socket) do
    owner_id = current_owner_id(socket)

    case SecurityTokens.list_owner_credentials(owner_id) do
      {:ok, %{tokens: tokens, api_keys: api_keys}} ->
        socket
        |> assign(:security_tokens, tokens)
        |> assign(:security_api_keys, api_keys)
        |> assign(:security_status_error, nil)

      {:error, typed_error} ->
        socket
        |> assign(:security_tokens, [])
        |> assign(:security_api_keys, [])
        |> assign(:security_status_error, typed_error)
    end
  end

  defp prepend_security_audit_event(socket, audit_entry) do
    event =
      audit_entry
      |> Map.put(:event_id, System.unique_integer([:positive]))

    assign(socket, :security_audit_events, [event | socket.assigns.security_audit_events])
  end

  defp load_security_secret_metadata(socket) do
    case SecretRefs.list_secret_metadata() do
      {:ok, secret_refs} ->
        socket
        |> assign(:security_secret_refs, secret_refs)
        |> assign(:security_secret_error, nil)

      {:error, typed_error} ->
        socket
        |> assign(:security_secret_refs, [])
        |> assign(:security_secret_error, typed_error)
    end
  end

  defp current_owner_id(socket) do
    socket.assigns
    |> Map.get(:current_user)
    |> case do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp security_status_label(:active), do: "Active"
  defp security_status_label(:expired), do: "Expired"
  defp security_status_label(:revoked), do: "Revoked"

  defp format_security_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_security_datetime(nil), do: "Not revoked"
  defp format_security_datetime(_value), do: "Unavailable"

  defp format_optional_security_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_optional_security_datetime(nil), do: "Never"
  defp format_optional_security_datetime(_value), do: "Unavailable"

  defp empty_security_secret_form(params \\ %{}) do
    defaults = %{"scope" => "integration", "name" => "", "value" => ""}
    params = Map.merge(defaults, params)
    to_form(params, as: :security_secret)
  end

  defp security_audit_message(audit) do
    source_label =
      case Map.get(audit, :source) do
        :session_token -> "Session token"
        :api_key -> "API key"
      end

    "#{source_label} #{Map.get(audit, :id)} revoked at #{format_security_datetime(Map.get(audit, :revoked_at))}."
  end

  defp repo_settings_summary(settings) when is_map(settings) and map_size(settings) > 0 do
    rendered_settings = inspect(Map.keys(settings))
    redaction = UiRedaction.sanitize_text(rendered_settings)

    %{
      text: redaction.text,
      security_alert?: redaction.security_alert?,
      alert_message: UiRedaction.security_alert_message(redaction.reason)
    }
  end

  defp repo_settings_summary(_settings) do
    %{
      text: "No custom settings",
      security_alert?: false,
      alert_message: nil
    }
  end
end
