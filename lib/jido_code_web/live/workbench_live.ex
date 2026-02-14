defmodule JidoCodeWeb.WorkbenchLive do
  use JidoCodeWeb, :live_view

  alias JidoCode.Workbench.Inventory

  @fallback_row_id_prefix "workbench-row-"

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:inventory_count, 0)
      |> assign(:stale_warning, nil)
      |> stream(:inventory_rows, [], reset: true)
      |> load_inventory()

    {:ok, socket}
  end

  @impl true
  def handle_event("retry_fetch", _params, socket) do
    {:noreply, load_inventory(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <section class="space-y-2">
        <h1 class="text-2xl font-bold">Workbench</h1>
        <p class="text-base-content/70">
          Unified cross-project inventory for issue and pull request triage.
        </p>
      </section>

      <section
        :if={@stale_warning}
        id="workbench-stale-warning"
        class="rounded-lg border border-warning/60 bg-warning/10 p-4 space-y-2"
      >
        <p id="workbench-stale-warning-label" class="font-semibold">Workbench data may be stale</p>
        <p id="workbench-stale-warning-type" class="text-sm">
          Typed warning: {@stale_warning.error_type}
        </p>
        <p id="workbench-stale-warning-detail" class="text-sm">{@stale_warning.detail}</p>
        <p id="workbench-stale-warning-remediation" class="text-sm">{@stale_warning.remediation}</p>
        <div class="flex flex-wrap gap-3 pt-1">
          <button
            id="workbench-retry-fetch"
            type="button"
            class="btn btn-sm btn-warning"
            phx-click="retry_fetch"
          >
            Retry workbench fetch
          </button>
          <.link
            id="workbench-open-setup-recovery"
            class="btn btn-sm btn-outline"
            navigate={~p"/setup?step=7&reason=workbench_data_stale"}
          >
            Review setup diagnostics
          </.link>
        </div>
      </section>

      <section class="rounded-lg border border-base-300 bg-base-100 overflow-x-auto">
        <table id="workbench-project-table" class="table table-zebra w-full">
          <thead>
            <tr>
              <th>Project</th>
              <th>Open issues</th>
              <th>Open PRs</th>
              <th>Recent activity</th>
              <th>Links</th>
            </tr>
          </thead>
          <tbody id="workbench-project-rows" phx-update="stream">
            <tr :if={@inventory_count == 0} id="workbench-empty-state">
              <td colspan="5" class="text-center text-sm text-base-content/70 py-8">
                No imported projects available yet.
              </td>
            </tr>
            <tr :for={{dom_id, project} <- @streams.inventory_rows} id={dom_id}>
              <td>
                <p id={"workbench-project-name-#{project.id}"} class="font-medium">
                  {project.github_full_name}
                </p>
                <p class="text-xs text-base-content/60">{project.name}</p>
              </td>
              <td id={"workbench-project-open-issues-#{project.id}"}>{project.open_issue_count}</td>
              <td id={"workbench-project-open-prs-#{project.id}"}>{project.open_pr_count}</td>
              <td id={"workbench-project-recent-activity-#{project.id}"} class="text-sm">
                {project.recent_activity_summary}
              </td>
              <td id={"workbench-project-links-#{project.id}"} class="space-y-2 text-xs">
                <div id={"workbench-project-issues-links-#{project.id}"}>
                  <p class="font-medium text-base-content/80">Issues</p>
                  <div class="flex flex-col gap-0.5">
                    <.row_link
                      link_id={"workbench-project-issues-github-link-#{project.id}"}
                      disabled_id={"workbench-project-issues-github-disabled-#{project.id}"}
                      reason_id={"workbench-project-issues-github-disabled-reason-#{project.id}"}
                      label="GitHub issues"
                      target={issue_github_url(project)}
                      disabled_reason={github_url_unavailable_reason()}
                      external
                    />
                    <.row_link
                      link_id={"workbench-project-issues-project-link-#{project.id}"}
                      disabled_id={"workbench-project-issues-project-disabled-#{project.id}"}
                      reason_id={"workbench-project-issues-project-disabled-reason-#{project.id}"}
                      label="Project detail"
                      target={project_detail_path(project)}
                      disabled_reason={project_detail_unavailable_reason()}
                    />
                  </div>
                </div>
                <div id={"workbench-project-prs-links-#{project.id}"}>
                  <p class="font-medium text-base-content/80">PRs</p>
                  <div class="flex flex-col gap-0.5">
                    <.row_link
                      link_id={"workbench-project-prs-github-link-#{project.id}"}
                      disabled_id={"workbench-project-prs-github-disabled-#{project.id}"}
                      reason_id={"workbench-project-prs-github-disabled-reason-#{project.id}"}
                      label="GitHub PRs"
                      target={pull_request_github_url(project)}
                      disabled_reason={github_url_unavailable_reason()}
                      external
                    />
                    <.row_link
                      link_id={"workbench-project-prs-project-link-#{project.id}"}
                      disabled_id={"workbench-project-prs-project-disabled-#{project.id}"}
                      reason_id={"workbench-project-prs-project-disabled-reason-#{project.id}"}
                      label="Project detail"
                      target={project_detail_path(project)}
                      disabled_reason={project_detail_unavailable_reason()}
                    />
                  </div>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </section>
    </Layouts.app>
    """
  end

  defp load_inventory(socket) do
    case Inventory.load() do
      {:ok, rows, stale_warning} ->
        socket
        |> assign(:inventory_count, length(rows))
        |> assign(:stale_warning, stale_warning)
        |> stream(:inventory_rows, rows, reset: true)

      {:error, stale_warning} ->
        socket
        |> assign(:inventory_count, 0)
        |> assign(:stale_warning, stale_warning)
        |> stream(:inventory_rows, [], reset: true)
    end
  end

  attr(:link_id, :string, required: true)
  attr(:disabled_id, :string, required: true)
  attr(:reason_id, :string, required: true)
  attr(:label, :string, required: true)
  attr(:target, :string, default: nil)
  attr(:disabled_reason, :string, required: true)
  attr(:external, :boolean, default: false)

  defp row_link(assigns) do
    ~H"""
    <%= if is_binary(@target) do %>
      <.link
        id={@link_id}
        class="link link-primary"
        href={@target}
        target={if @external, do: "_blank"}
        rel={if @external, do: "noopener noreferrer"}
      >
        {@label}
      </.link>
    <% else %>
      <span
        id={@disabled_id}
        class="text-base-content/50 cursor-not-allowed"
        aria-disabled="true"
        title={@disabled_reason}
      >
        {@label}
      </span>
      <p id={@reason_id} class="text-[11px] text-base-content/60">
        Unavailable: {@disabled_reason}
      </p>
    <% end %>
    """
  end

  defp issue_github_url(project) do
    with {:ok, repository_path} <- github_repository_path(project) do
      "#{repository_path}/issues"
    end
  end

  defp pull_request_github_url(project) do
    with {:ok, repository_path} <- github_repository_path(project) do
      "#{repository_path}/pulls"
    end
  end

  defp github_repository_path(project) do
    project
    |> Map.get(:github_full_name)
    |> normalize_optional_string()
    |> parse_github_repository_name()
    |> case do
      {:ok, owner, repository} -> {:ok, "https://github.com/#{owner}/#{repository}"}
      :error -> :error
    end
  end

  defp parse_github_repository_name(nil), do: :error

  defp parse_github_repository_name(github_full_name) do
    case String.split(github_full_name, "/", parts: 2) do
      [owner, repository] ->
        owner = String.trim(owner)
        repository = String.trim(repository)

        if owner == "" or repository == "" or String.contains?(owner <> repository, " ") do
          :error
        else
          {:ok, owner, repository}
        end

      _other ->
        :error
    end
  end

  defp project_detail_path(project) do
    project
    |> Map.get(:id)
    |> normalize_optional_string()
    |> case do
      nil ->
        nil

      <<@fallback_row_id_prefix, _::binary>> ->
        nil

      project_id ->
        "/projects/#{URI.encode(project_id)}"
    end
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_boolean(value), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(value) when is_float(value), do: :erlang.float_to_binary(value)
  defp normalize_optional_string(_value), do: nil

  defp github_url_unavailable_reason, do: "GitHub repository URL is unavailable for this row."
  defp project_detail_unavailable_reason, do: "Project detail link is unavailable for this row."
end
