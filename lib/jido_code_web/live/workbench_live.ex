defmodule JidoCodeWeb.WorkbenchLive do
  use JidoCodeWeb, :live_view

  alias JidoCode.Workbench.Inventory

  @fallback_row_id_prefix "workbench-row-"
  @filter_validation_error_type "workbench_filter_values_invalid"
  @filter_restore_validation_error_type "workbench_filter_restore_state_invalid"
  @sort_validation_error_type "workbench_sort_order_fallback"

  @default_filter_values %{
    "project_id" => "all",
    "work_state" => "all",
    "freshness_window" => "any",
    "sort_order" => "project_name_asc"
  }

  @work_state_filter_options [
    {"Any issue or PR state", "all"},
    {"Issues open", "issues_open"},
    {"PRs open", "prs_open"},
    {"Issues and PRs open", "issues_and_prs_open"}
  ]

  @freshness_filter_options [
    {"Any freshness", "any"},
    {"Active in last 24 hours", "active_24h"},
    {"Stale for 7+ days", "stale_7d"},
    {"Stale for 30+ days", "stale_30d"}
  ]

  @sort_order_options [
    {"Project name (A-Z)", "project_name_asc"},
    {"Backlog size (highest first)", "backlog_desc"},
    {"Backlog size (lowest first)", "backlog_asc"},
    {"Recent activity (most recent first)", "recent_activity_desc"},
    {"Recent activity (oldest first)", "recent_activity_asc"}
  ]

  @default_project_filter_value Map.fetch!(@default_filter_values, "project_id")
  @default_work_state_filter_value Map.fetch!(@default_filter_values, "work_state")
  @default_freshness_filter_value Map.fetch!(@default_filter_values, "freshness_window")
  @default_sort_order_value Map.fetch!(@default_filter_values, "sort_order")
  @filter_state_query_keys ["project_id", "work_state", "freshness_window", "sort_order"]

  @impl true
  def mount(params, _session, socket) do
    initial_filter_values = initial_filter_values(params)

    socket =
      socket
      |> assign(:inventory_count, 0)
      |> assign(:inventory_total_count, 0)
      |> assign(:inventory_rows_all, [])
      |> assign(:stale_warning, nil)
      |> assign(:filter_validation_notice, nil)
      |> assign(:sort_validation_notice, nil)
      |> assign(:filter_values, initial_filter_values)
      |> assign(:filter_form, to_filter_form(initial_filter_values))
      |> assign(:filter_chips, filter_chips(initial_filter_values, []))
      |> assign(:project_filter_options, project_filter_options([]))
      |> stream(:inventory_rows, [], reset: true)
      |> load_inventory()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case restored_filter_values(params, socket.assigns.inventory_rows_all) do
      {:ok, filter_values} ->
        socket =
          socket
          |> assign(:filter_validation_notice, nil)
          |> apply_filters(filter_values)

        {:noreply, socket}

      {:error, field, invalid_value} ->
        socket =
          socket
          |> assign(:filter_validation_notice, filter_restore_validation_notice(field, invalid_value))
          |> apply_filters(@default_filter_values)

        {:noreply, socket}

      :none ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("retry_fetch", _params, socket) do
    {:noreply, load_inventory(socket)}
  end

  @impl true
  def handle_event("apply_filters", %{"filters" => filter_params}, socket) do
    socket =
      socket
      |> apply_filter_event(filter_params)
      |> push_filter_state_patch()

    {:noreply, socket}
  end

  @impl true
  def handle_event("apply_filters", _params, socket) do
    socket =
      socket
      |> apply_invalid_filter_defaults("filters", "missing")
      |> push_filter_state_patch()

    {:noreply, socket}
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

      <section
        :if={@filter_validation_notice}
        id="workbench-filter-validation-notice"
        class="rounded-lg border border-warning/60 bg-warning/10 p-4 space-y-2"
      >
        <p id="workbench-filter-validation-label" class="font-semibold">
          Workbench filters were reset to defaults
        </p>
        <p id="workbench-filter-validation-type" class="text-sm">
          Typed validation notice: {@filter_validation_notice.error_type}
        </p>
        <p id="workbench-filter-validation-detail" class="text-sm">
          {@filter_validation_notice.detail}
        </p>
        <p id="workbench-filter-validation-remediation" class="text-sm">
          {@filter_validation_notice.remediation}
        </p>
      </section>

      <section
        :if={@sort_validation_notice}
        id="workbench-sort-validation-notice"
        class="rounded-lg border border-warning/60 bg-warning/10 p-4 space-y-2"
      >
        <p id="workbench-sort-validation-label" class="font-semibold">
          Workbench sort fell back to default order
        </p>
        <p id="workbench-sort-validation-type" class="text-sm">
          Typed sort notice: {@sort_validation_notice.error_type}
        </p>
        <p id="workbench-sort-validation-detail" class="text-sm">
          {@sort_validation_notice.detail}
        </p>
        <p id="workbench-sort-validation-remediation" class="text-sm">
          {@sort_validation_notice.remediation}
        </p>
      </section>

      <section id="workbench-filters-panel" class="rounded-lg border border-base-300 bg-base-100 p-4">
        <.form
          for={@filter_form}
          id="workbench-filters-form"
          phx-change="apply_filters"
          phx-submit="apply_filters"
          class="grid gap-3 lg:grid-cols-[minmax(12rem,1fr)_minmax(12rem,1fr)_minmax(12rem,1fr)_minmax(14rem,1fr)_auto]"
        >
          <.input
            id="workbench-filter-project"
            field={@filter_form[:project_id]}
            type="select"
            label="Project"
            options={@project_filter_options}
          />
          <.input
            id="workbench-filter-work-state"
            field={@filter_form[:work_state]}
            type="select"
            label="Issue/PR state"
            options={work_state_filter_options()}
          />
          <.input
            id="workbench-filter-freshness-window"
            field={@filter_form[:freshness_window]}
            type="select"
            label="Freshness window"
            options={freshness_filter_options()}
          />
          <.input
            id="workbench-filter-sort-order"
            field={@filter_form[:sort_order]}
            type="select"
            label="Sort rows by"
            options={sort_order_options()}
          />
          <button id="workbench-apply-filters" type="submit" class="btn btn-primary btn-sm lg:self-end">
            Apply filters
          </button>
        </.form>

        <div id="workbench-filter-chips" class="flex flex-wrap gap-2 pt-2">
          <span id="workbench-filter-chip-project" class="badge badge-outline">
            Project: {@filter_chips.project}
          </span>
          <span id="workbench-filter-chip-work-state" class="badge badge-outline">
            State: {@filter_chips.work_state}
          </span>
          <span id="workbench-filter-chip-freshness-window" class="badge badge-outline">
            Freshness: {@filter_chips.freshness_window}
          </span>
          <span id="workbench-filter-chip-sort-order" class="badge badge-outline">
            Sort: {@filter_chips.sort_order}
          </span>
        </div>

        <p id="workbench-filter-results-count" class="pt-2 text-xs text-base-content/70">
          Showing {@inventory_count} of {@inventory_total_count} projects.
        </p>
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
                {empty_state_message(@inventory_total_count)}
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
                      target={project_detail_path(project, @filter_values)}
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
                      target={project_detail_path(project, @filter_values)}
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
        filter_values =
          socket.assigns
          |> Map.get(:filter_values, @default_filter_values)
          |> normalize_filter_values()
          |> validated_filter_values_or_default(rows)

        socket
        |> assign(:inventory_rows_all, rows)
        |> assign(:stale_warning, stale_warning)
        |> assign(:project_filter_options, project_filter_options(rows))
        |> apply_filters(filter_values)

      {:error, stale_warning} ->
        filter_values =
          socket.assigns
          |> Map.get(:filter_values, @default_filter_values)
          |> normalize_filter_values()
          |> validated_filter_values_or_default([])

        socket
        |> assign(:inventory_count, 0)
        |> assign(:inventory_total_count, 0)
        |> assign(:inventory_rows_all, [])
        |> assign(:stale_warning, stale_warning)
        |> assign(:sort_validation_notice, nil)
        |> assign(:project_filter_options, project_filter_options([]))
        |> assign(:filter_values, filter_values)
        |> assign(:filter_form, to_filter_form(filter_values))
        |> assign(:filter_chips, filter_chips(filter_values, []))
        |> stream(:inventory_rows, [], reset: true)
    end
  end

  defp apply_filter_event(socket, filter_params) do
    filter_values = normalize_filter_values(filter_params)

    case validate_filter_values(filter_values, socket.assigns.inventory_rows_all) do
      :ok ->
        socket
        |> assign(:filter_validation_notice, nil)
        |> apply_filters(filter_values)

      {:error, field, invalid_value} ->
        apply_invalid_filter_defaults(socket, field, invalid_value)
    end
  end

  defp apply_invalid_filter_defaults(socket, field, invalid_value) do
    socket
    |> assign(:filter_validation_notice, filter_validation_notice(field, invalid_value))
    |> apply_filters(@default_filter_values)
  end

  defp push_filter_state_patch(socket) do
    filter_values =
      socket.assigns
      |> Map.get(:filter_values, @default_filter_values)
      |> normalize_filter_values()

    push_patch(socket, to: workbench_path_with_filter_values(filter_values))
  end

  defp apply_filters(socket, filter_values) do
    rows = filter_rows(socket.assigns.inventory_rows_all, filter_values)

    {sorted_rows, applied_filter_values, sort_validation_notice} =
      sort_rows_with_fallback(rows, filter_values)

    project_options = project_filter_options(socket.assigns.inventory_rows_all)

    socket
    |> assign(:inventory_count, length(sorted_rows))
    |> assign(:inventory_total_count, length(socket.assigns.inventory_rows_all))
    |> assign(:sort_validation_notice, sort_validation_notice)
    |> assign(:filter_values, applied_filter_values)
    |> assign(:filter_form, to_filter_form(applied_filter_values))
    |> assign(:filter_chips, filter_chips(applied_filter_values, socket.assigns.inventory_rows_all))
    |> assign(:project_filter_options, project_options)
    |> stream(:inventory_rows, sorted_rows, reset: true)
  end

  defp filter_rows(rows, filter_values) do
    now = DateTime.utc_now()
    project_id = Map.fetch!(filter_values, "project_id")
    work_state = Map.fetch!(filter_values, "work_state")
    freshness_window = Map.fetch!(filter_values, "freshness_window")

    Enum.filter(rows, fn row ->
      project_filter_match?(row, project_id) and
        work_state_filter_match?(row, work_state) and
        freshness_filter_match?(row, freshness_window, now)
    end)
  end

  defp project_filter_match?(_row, @default_project_filter_value), do: true
  defp project_filter_match?(row, project_id), do: Map.get(row, :id) == project_id

  defp work_state_filter_match?(_row, @default_work_state_filter_value), do: true

  defp work_state_filter_match?(row, "issues_open"),
    do: Map.get(row, :open_issue_count, 0) > 0

  defp work_state_filter_match?(row, "prs_open"),
    do: Map.get(row, :open_pr_count, 0) > 0

  defp work_state_filter_match?(row, "issues_and_prs_open"),
    do: Map.get(row, :open_issue_count, 0) > 0 and Map.get(row, :open_pr_count, 0) > 0

  defp work_state_filter_match?(_row, _work_state), do: false

  defp freshness_filter_match?(_row, @default_freshness_filter_value, _now), do: true

  defp freshness_filter_match?(row, "active_24h", now),
    do: recent_activity_within?(row, now, 24 * 60 * 60)

  defp freshness_filter_match?(row, "stale_7d", now),
    do: stale_for_or_missing?(row, now, 7 * 24 * 60 * 60)

  defp freshness_filter_match?(row, "stale_30d", now),
    do: stale_for_or_missing?(row, now, 30 * 24 * 60 * 60)

  defp freshness_filter_match?(_row, _freshness_window, _now), do: false

  defp recent_activity_within?(row, now, seconds) do
    case row_recent_activity_at(row) do
      %DateTime{} = activity_at ->
        cutoff = DateTime.add(now, -seconds, :second)
        DateTime.compare(activity_at, cutoff) in [:eq, :gt]

      _other ->
        false
    end
  end

  defp stale_for_or_missing?(row, now, seconds) do
    case row_recent_activity_at(row) do
      %DateTime{} = activity_at ->
        cutoff = DateTime.add(now, -seconds, :second)
        DateTime.compare(activity_at, cutoff) in [:lt, :eq]

      _other ->
        true
    end
  end

  defp row_recent_activity_at(row) do
    row
    |> Map.get(:recent_activity_at)
    |> normalize_optional_datetime()
  end

  defp normalize_filter_values(filter_values) when is_map(filter_values) do
    %{
      "project_id" =>
        filter_values
        |> map_get("project_id", :project_id)
        |> normalize_optional_string() || @default_project_filter_value,
      "work_state" =>
        filter_values
        |> map_get("work_state", :work_state)
        |> normalize_optional_string() || @default_work_state_filter_value,
      "freshness_window" =>
        filter_values
        |> map_get("freshness_window", :freshness_window)
        |> normalize_optional_string() || @default_freshness_filter_value,
      "sort_order" =>
        filter_values
        |> map_get("sort_order", :sort_order)
        |> normalize_optional_string() || @default_sort_order_value
    }
  end

  defp normalize_filter_values(_filter_values), do: @default_filter_values

  defp initial_filter_values(params) do
    restored_values = extract_filter_state_params(params || %{})

    if map_size(restored_values) == 0 do
      @default_filter_values
    else
      @default_filter_values
      |> Map.merge(restored_values)
      |> normalize_filter_values()
    end
  end

  defp restored_filter_values(params, rows) do
    restored_values = extract_filter_state_params(params)

    if map_size(restored_values) == 0 do
      :none
    else
      filter_values =
        @default_filter_values
        |> Map.merge(restored_values)
        |> normalize_filter_values()

      case validate_filter_values(filter_values, rows) do
        :ok ->
          {:ok, filter_values}

        {:error, field, invalid_value} ->
          {:error, field, invalid_value}
      end
    end
  end

  defp extract_filter_state_params(params) do
    Enum.reduce(@filter_state_query_keys, %{}, fn key, acc ->
      case Map.get(params, key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp validated_filter_values_or_default(filter_values, rows) do
    case validate_filter_values(filter_values, rows) do
      :ok -> filter_values
      {:error, _field, _invalid_value} -> @default_filter_values
    end
  end

  defp validate_filter_values(filter_values, rows) do
    valid_project_values =
      rows
      |> Enum.map(&Map.get(&1, :id))
      |> Enum.reject(&is_nil/1)
      |> then(&MapSet.new([@default_project_filter_value | &1]))

    valid_work_state_values = @work_state_filter_options |> Enum.map(&elem(&1, 1)) |> MapSet.new()

    valid_freshness_values =
      @freshness_filter_options |> Enum.map(&elem(&1, 1)) |> MapSet.new()

    valid_sort_order_values =
      @sort_order_options |> Enum.map(&elem(&1, 1)) |> MapSet.new()

    with :ok <-
           validate_filter_value(
             "project_id",
             Map.fetch!(filter_values, "project_id"),
             valid_project_values
           ),
         :ok <-
           validate_filter_value(
             "work_state",
             Map.fetch!(filter_values, "work_state"),
             valid_work_state_values
           ),
         :ok <-
           validate_filter_value(
             "freshness_window",
             Map.fetch!(filter_values, "freshness_window"),
             valid_freshness_values
           ),
         :ok <-
           validate_filter_value(
             "sort_order",
             Map.fetch!(filter_values, "sort_order"),
             valid_sort_order_values
           ) do
      :ok
    end
  end

  defp validate_filter_value(field, value, valid_values) do
    if MapSet.member?(valid_values, value) do
      :ok
    else
      {:error, field, inspect(value)}
    end
  end

  defp filter_validation_notice(field, invalid_value) do
    %{
      error_type: @filter_validation_error_type,
      detail: "Invalid #{field} value #{invalid_value} was submitted for workbench filters; defaults were restored.",
      remediation: "Select values from the listed project, state, and freshness options and retry."
    }
  end

  defp filter_restore_validation_notice(field, invalid_value) do
    %{
      error_type: @filter_restore_validation_error_type,
      detail:
        "Workbench state restoration failed because #{field} value #{invalid_value} is invalid; defaults were restored.",
      remediation: "Use workbench filters to reselect project, state, freshness, and sort preferences."
    }
  end

  defp workbench_path_with_filter_values(filter_values) do
    query_params =
      @filter_state_query_keys
      |> Enum.reduce([], fn key, acc ->
        value = Map.get(filter_values, key, Map.fetch!(@default_filter_values, key))
        default_value = Map.fetch!(@default_filter_values, key)

        if value == default_value do
          acc
        else
          [{key, value} | acc]
        end
      end)
      |> Enum.reverse()

    case query_params do
      [] -> "/workbench"
      _other -> "/workbench?" <> URI.encode_query(query_params)
    end
  end

  defp filter_chips(filter_values, rows) do
    project_label =
      case Map.fetch!(filter_values, "project_id") do
        @default_project_filter_value ->
          "All projects"

        project_id ->
          rows
          |> Enum.find(fn row -> Map.get(row, :id) == project_id end)
          |> case do
            nil -> "All projects"
            row -> row |> Map.get(:github_full_name) |> normalize_optional_string() || project_id
          end
      end

    %{
      project: project_label,
      work_state:
        option_label(
          @work_state_filter_options,
          Map.fetch!(filter_values, "work_state"),
          "Any issue or PR state"
        ),
      freshness_window:
        option_label(
          @freshness_filter_options,
          Map.fetch!(filter_values, "freshness_window"),
          "Any freshness"
        ),
      sort_order:
        option_label(
          @sort_order_options,
          Map.fetch!(filter_values, "sort_order"),
          "Project name (A-Z)"
        )
    }
  end

  defp sort_rows_with_fallback(rows, filter_values) do
    requested_sort_order = Map.fetch!(filter_values, "sort_order")

    case sort_rows(rows, requested_sort_order) do
      {:ok, sorted_rows} ->
        {sorted_rows, filter_values, nil}

      {:error, reason} ->
        fallback_sort_order = @default_sort_order_value
        {:ok, fallback_rows} = sort_rows(rows, fallback_sort_order)

        {
          fallback_rows,
          Map.put(filter_values, "sort_order", fallback_sort_order),
          sort_validation_notice(requested_sort_order, fallback_sort_order, reason)
        }
    end
  end

  defp sort_rows(rows, @default_sort_order_value) do
    {:ok, Enum.sort_by(rows, &project_sort_key/1)}
  end

  defp sort_rows(rows, "backlog_desc") do
    with :ok <- validate_rows_for_sort(rows, :backlog) do
      sorted_rows =
        Enum.sort_by(rows, fn row ->
          {-backlog_size(row), project_sort_key(row)}
        end)

      {:ok, sorted_rows}
    end
  end

  defp sort_rows(rows, "backlog_asc") do
    with :ok <- validate_rows_for_sort(rows, :backlog) do
      sorted_rows =
        Enum.sort_by(rows, fn row ->
          {backlog_size(row), project_sort_key(row)}
        end)

      {:ok, sorted_rows}
    end
  end

  defp sort_rows(rows, "recent_activity_desc") do
    with :ok <- validate_rows_for_sort(rows, :recent_activity) do
      sorted_rows =
        Enum.sort_by(rows, fn row ->
          recent_activity_sort_key(row, :desc)
        end)

      {:ok, sorted_rows}
    end
  end

  defp sort_rows(rows, "recent_activity_asc") do
    with :ok <- validate_rows_for_sort(rows, :recent_activity) do
      sorted_rows =
        Enum.sort_by(rows, fn row ->
          recent_activity_sort_key(row, :asc)
        end)

      {:ok, sorted_rows}
    end
  end

  defp sort_rows(_rows, _sort_order), do: {:error, :unknown_sort_order}

  defp validate_rows_for_sort(rows, :backlog) do
    if Enum.any?(rows, &malformed_row_for_backlog_sort?/1) do
      {:error, :malformed_backlog_data}
    else
      :ok
    end
  end

  defp validate_rows_for_sort(rows, :recent_activity) do
    if Enum.any?(rows, &malformed_row_for_recent_activity_sort?/1) do
      {:error, :malformed_recent_activity_data}
    else
      :ok
    end
  end

  defp backlog_size(row) do
    Map.get(row, :open_issue_count, 0) + Map.get(row, :open_pr_count, 0)
  end

  defp recent_activity_sort_key(row, direction) do
    activity_at = row_recent_activity_at(row)
    missing_activity = is_nil(activity_at)
    activity_unix = if activity_at, do: DateTime.to_unix(activity_at, :microsecond), else: 0

    case direction do
      :desc ->
        {if(missing_activity, do: 1, else: 0), -activity_unix, project_sort_key(row)}

      :asc ->
        {if(missing_activity, do: 1, else: 0), activity_unix, project_sort_key(row)}
    end
  end

  defp malformed_row_for_backlog_sort?(row) do
    fallback_row_id?(row) or
      not non_negative_integer?(Map.get(row, :open_issue_count)) or
      not non_negative_integer?(Map.get(row, :open_pr_count))
  end

  defp malformed_row_for_recent_activity_sort?(row) do
    fallback_row_id?(row) or
      case row_recent_activity_at(row) do
        %DateTime{} -> false
        nil -> false
        _other -> true
      end
  end

  defp fallback_row_id?(row) do
    case row |> Map.get(:id) |> normalize_optional_string() do
      <<@fallback_row_id_prefix, _::binary>> -> true
      _other -> false
    end
  end

  defp non_negative_integer?(value), do: is_integer(value) and value >= 0

  defp project_sort_key(row) do
    {
      row |> Map.get(:github_full_name) |> sort_string_key(),
      row |> Map.get(:name) |> sort_string_key(),
      row |> Map.get(:id) |> sort_string_key()
    }
  end

  defp sort_string_key(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil -> ""
      normalized -> String.downcase(normalized)
    end
  end

  defp sort_validation_notice(requested_sort_order, fallback_sort_order, reason) do
    requested_sort_label =
      option_label(@sort_order_options, requested_sort_order, requested_sort_order)

    fallback_sort_label = option_label(@sort_order_options, fallback_sort_order, fallback_sort_order)

    %{
      error_type: @sort_validation_error_type,
      detail:
        "Sort order #{requested_sort_label} could not be applied (#{sort_failure_reason(reason)}). #{fallback_sort_label} was applied instead.",
      remediation: "Refresh workbench data and verify backlog and activity metadata before retrying."
    }
  end

  defp sort_failure_reason(:malformed_backlog_data), do: "malformed backlog fields were detected"
  defp sort_failure_reason(:malformed_recent_activity_data), do: "malformed activity fields were detected"
  defp sort_failure_reason(:unknown_sort_order), do: "unsupported sort value was submitted"
  defp sort_failure_reason(_reason), do: "sorting metadata validation failed"

  defp option_label(options, value, default_label) do
    Enum.find_value(options, default_label, fn
      {label, ^value} -> label
      _other -> nil
    end)
  end

  defp project_filter_options(rows) do
    dynamic_options =
      rows
      |> Enum.map(fn row ->
        label =
          row
          |> Map.get(:github_full_name)
          |> normalize_optional_string() ||
            row
            |> Map.get(:name)
            |> normalize_optional_string() ||
            Map.get(row, :id)

        {label, Map.get(row, :id)}
      end)
      |> Enum.reject(fn {label, value} -> is_nil(label) or is_nil(value) end)
      |> Enum.uniq_by(fn {_label, value} -> value end)
      |> Enum.sort_by(fn {label, _value} -> String.downcase(label) end)

    [{"All projects", @default_project_filter_value} | dynamic_options]
  end

  defp work_state_filter_options, do: @work_state_filter_options
  defp freshness_filter_options, do: @freshness_filter_options
  defp sort_order_options, do: @sort_order_options
  defp to_filter_form(filter_values), do: to_form(filter_values, as: :filters)

  defp empty_state_message(0), do: "No imported projects available yet."
  defp empty_state_message(_inventory_total_count), do: "No projects match the active filters."

  defp map_get(map, string_key, atom_key) do
    cond do
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      true -> nil
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

  defp project_detail_path(project, filter_values) do
    project
    |> Map.get(:id)
    |> normalize_optional_string()
    |> case do
      nil ->
        nil

      <<@fallback_row_id_prefix, _::binary>> ->
        nil

      project_id ->
        base_path = "/projects/#{URI.encode(project_id)}"
        return_to = workbench_path_with_filter_values(normalize_filter_values(filter_values))

        if return_to == "/workbench" do
          base_path
        else
          "#{base_path}?return_to=#{URI.encode_www_form(return_to)}"
        end
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

  defp normalize_optional_datetime(%DateTime{} = datetime), do: datetime

  defp normalize_optional_datetime(%NaiveDateTime{} = datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, parsed_datetime} -> parsed_datetime
      _other -> nil
    end
  end

  defp normalize_optional_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed_datetime, _offset} ->
        parsed_datetime

      _other ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, parsed_naive_datetime} ->
            normalize_optional_datetime(parsed_naive_datetime)

          _fallback ->
            nil
        end
    end
  end

  defp normalize_optional_datetime(_value), do: nil

  defp github_url_unavailable_reason, do: "GitHub repository URL is unavailable for this row."
  defp project_detail_unavailable_reason, do: "Project detail link is unavailable for this row."
end
