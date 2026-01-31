defmodule AgentJidoWeb.SettingsLive do
  use AgentJidoWeb, :live_view

  alias AgentJido.GitHub.Repo

  @impl true
  def mount(_params, _session, socket) do
    repos = Repo.read!()

    socket =
      socket
      |> assign(:show_add_modal, false)
      |> assign(:form, nil)
      |> stream(:repos, repos)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = Map.get(params, "tab", "github")
    {:noreply, assign(socket, :active_tab, tab)}
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
                    "block px-4 py-2 rounded-lg transition-colors",
                    @active_tab == "github" && "bg-primary-light text-white dark:bg-primary-dark",
                    @active_tab != "github" && "hover:bg-base-border-light dark:hover:bg-base-border-dark"
                  ]}
                >
                  <.icon name="hero-code-bracket" class="w-5 h-5 inline-block mr-2" />
                  GitHub
                </.link>
              </li>
              <li>
                <.link
                  patch={~p"/settings/agents"}
                  class={[
                    "block px-4 py-2 rounded-lg transition-colors",
                    @active_tab == "agents" && "bg-primary-light text-white dark:bg-primary-dark",
                    @active_tab != "agents" && "hover:bg-base-border-light dark:hover:bg-base-border-dark"
                  ]}
                >
                  <.icon name="hero-cpu-chip" class="w-5 h-5 inline-block mr-2" />
                  Agents
                </.link>
              </li>
              <li>
                <.link
                  patch={~p"/settings/account"}
                  class={[
                    "block px-4 py-2 rounded-lg transition-colors",
                    @active_tab == "account" && "bg-primary-light text-white dark:bg-primary-dark",
                    @active_tab != "account" && "hover:bg-base-border-light dark:hover:bg-base-border-dark"
                  ]}
                >
                  <.icon name="hero-user-circle" class="w-5 h-5 inline-block mr-2" />
                  Account
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
          <.text_field
            field={@form[:webhook_secret]}
            label="Webhook Secret"
            placeholder="A secret string for webhook verification"
          />
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
        <.button phx-click="open_add_modal" color="primary">
          <.icon name="hero-plus" class="w-4 h-4 mr-1" />
          Add Repository
        </.button>
      </div>

      <div class="space-y-4" id="repos-list" phx-update="stream">
        <.card :for={{dom_id, repo} <- @repos} id={dom_id} padding="medium" rounded="large">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <.icon name="hero-folder" class="w-6 h-6 text-base-content/50" />
              <div>
                <p class="font-medium">{repo.full_name}</p>
                <p class="text-sm text-base-content/60">
                  <%= if repo.settings && map_size(repo.settings) > 0 do %>
                    {inspect(Map.keys(repo.settings))}
                  <% else %>
                    No custom settings
                  <% end %>
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

        <.card :if={Enum.empty?(@repos)} padding="large" rounded="large" class="text-center">
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
end
