defmodule JidoCodeWeb.AgentsLive do
  use JidoCodeWeb, :live_view

  alias JidoCode.Agents.SupportAgentConfigs

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:issue_bot_error, nil)
      |> assign(:project_count, 0)
      |> stream(:project_configs, [], reset: true)
      |> load_project_configs()

    {:ok, socket}
  end

  @impl true
  def handle_event(
        "set_issue_bot_enabled",
        %{"project_id" => project_id, "enabled" => enabled},
        socket
      ) do
    case SupportAgentConfigs.set_issue_bot_enabled(project_id, enabled) do
      {:ok, project_config} ->
        {:noreply,
         socket
         |> assign(:issue_bot_error, nil)
         |> stream_insert(:project_configs, project_config)}

      {:error, typed_error} ->
        {:noreply, assign(socket, :issue_bot_error, typed_error)}
    end
  end

  def handle_event("set_issue_bot_enabled", _params, socket) do
    {:noreply,
     assign(socket, :issue_bot_error, %{
       error_type: "support_agent_config_validation_failed",
       detail: "Issue Bot toggle request is missing required parameters.",
       remediation: "Select Enable or Disable from a valid project row and retry."
     })}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <section class="space-y-2">
        <h1 class="text-2xl font-bold">Support Agents</h1>
        <p class="text-base-content/70">
          Configure per-project Issue Bot automation controls.
        </p>
      </section>

      <section
        :if={@issue_bot_error}
        id="agents-issue-bot-error"
        class="rounded-lg border border-warning/60 bg-warning/10 p-4 space-y-2"
      >
        <p id="agents-issue-bot-error-label" class="font-semibold">
          Issue Bot configuration update failed
        </p>
        <p id="agents-issue-bot-error-type" class="text-sm">
          Typed error: {@issue_bot_error.error_type}
        </p>
        <p id="agents-issue-bot-error-detail" class="text-sm">{@issue_bot_error.detail}</p>
        <p id="agents-issue-bot-error-remediation" class="text-sm">{@issue_bot_error.remediation}</p>
      </section>

      <section class="rounded-lg border border-base-300 bg-base-100 overflow-x-auto">
        <table id="agents-project-table" class="table table-zebra w-full">
          <thead>
            <tr>
              <th>Project</th>
              <th>Issue Bot status</th>
              <th>Controls</th>
            </tr>
          </thead>
          <tbody id="agents-project-rows" phx-update="stream">
            <tr :if={@project_count == 0} id="agents-project-empty">
              <td colspan="3" class="text-center text-sm text-base-content/70 py-8">
                No projects are available for Issue Bot configuration.
              </td>
            </tr>

            <tr :for={{dom_id, project_config} <- @streams.project_configs} id={dom_id}>
              <td>
                <p id={"agents-project-github-full-name-#{project_config.id}"} class="font-medium">
                  {project_config.github_full_name}
                </p>
                <p id={"agents-project-name-#{project_config.id}"} class="text-xs text-base-content/60">
                  {project_config.name}
                </p>
              </td>
              <td id={"agents-issue-bot-status-#{project_config.id}"}>
                <span class={issue_bot_status_class(project_config.enabled)}>
                  {issue_bot_status_label(project_config.enabled)}
                </span>
              </td>
              <td>
                <div class="flex flex-wrap gap-2">
                  <button
                    id={"agents-issue-bot-enable-#{project_config.id}"}
                    type="button"
                    class="btn btn-xs btn-success"
                    phx-click="set_issue_bot_enabled"
                    phx-value-project_id={project_config.id}
                    phx-value-enabled="true"
                    disabled={project_config.enabled}
                  >
                    Enable
                  </button>
                  <button
                    id={"agents-issue-bot-disable-#{project_config.id}"}
                    type="button"
                    class="btn btn-xs btn-outline btn-warning"
                    phx-click="set_issue_bot_enabled"
                    phx-value-project_id={project_config.id}
                    phx-value-enabled="false"
                    disabled={!project_config.enabled}
                  >
                    Disable
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </section>
    </Layouts.app>
    """
  end

  defp load_project_configs(socket) do
    case SupportAgentConfigs.list_issue_bot_configs() do
      {:ok, project_configs} ->
        socket
        |> assign(:issue_bot_error, nil)
        |> assign(:project_count, length(project_configs))
        |> stream(:project_configs, project_configs, reset: true)

      {:error, typed_error} ->
        socket
        |> assign(:issue_bot_error, typed_error)
        |> assign(:project_count, 0)
        |> stream(:project_configs, [], reset: true)
    end
  end

  defp issue_bot_status_label(true), do: "Enabled"
  defp issue_bot_status_label(false), do: "Disabled"

  defp issue_bot_status_class(true), do: "badge badge-success"
  defp issue_bot_status_class(false), do: "badge badge-warning"
end
