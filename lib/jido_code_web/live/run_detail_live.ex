defmodule JidoCodeWeb.RunDetailLive do
  use JidoCodeWeb, :live_view

  alias JidoCode.Orchestration.WorkflowRun

  @impl true
  def mount(%{"id" => project_id, "run_id" => run_id}, _session, socket) do
    case WorkflowRun.get_by_project_and_run_id(%{project_id: project_id, run_id: run_id}) do
      {:ok, %WorkflowRun{} = run} ->
        {:ok,
         socket
         |> assign(:project_id, project_id)
         |> assign(:run_id, run_id)
         |> assign(:run, run)
         |> assign(:timeline_entries, timeline_entries(run))
         |> assign(:approval_context, approval_context(run))
         |> assign(:approval_context_blocker, approval_context_blocker(run))}

      {:ok, nil} ->
        {:ok, assign_missing_run(socket, project_id, run_id)}

      {:error, _reason} ->
        {:ok, assign_missing_run(socket, project_id, run_id)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <section id="run-detail-page" class="space-y-4">
        <%= if @run do %>
          <section id="run-detail-header" class="space-y-1">
            <h1 id="run-detail-title" class="text-2xl font-bold">Workflow run detail</h1>
            <p id="run-detail-run-id" class="text-sm">
              Run: <span class="font-mono">{@run.run_id}</span>
            </p>
            <p id="run-detail-status" class="text-sm">
              Status: {status_label(@run.status)}
            </p>
            <p id="run-detail-current-step" class="text-sm">
              Current step: {current_step_label(@run.current_step)}
            </p>
          </section>

          <%= if awaiting_approval?(@run.status) do %>
            <section id="run-detail-approval-panel" class="space-y-3 rounded border border-base-300 bg-base-100 p-4">
              <h2 class="text-lg font-semibold">Approval request payload</h2>
              <p id="run-detail-approval-panel-note" class="text-sm text-base-content/80">
                Review this context before approval decisions are enabled.
              </p>

              <%= if @approval_context do %>
                <div id="run-detail-approval-context" class="space-y-2 rounded border border-base-300 p-3">
                  <p id="run-detail-approval-diff-summary" class="text-sm">
                    Diff summary: {@approval_context.diff_summary}
                  </p>
                  <p id="run-detail-approval-test-summary" class="text-sm">
                    Test summary: {@approval_context.test_summary}
                  </p>
                  <div class="space-y-1">
                    <p class="text-sm font-medium">Risk notes</p>
                    <ul id="run-detail-approval-risk-notes" class="list-disc pl-5 text-sm text-base-content/80">
                      <li
                        :for={{risk_note, index} <- Enum.with_index(@approval_context.risk_notes, 1)}
                        id={"run-detail-approval-risk-note-#{index}"}
                      >
                        {risk_note}
                      </li>
                    </ul>
                  </div>
                </div>
              <% else %>
                <p id="run-detail-approval-context-missing" class="text-sm text-warning">
                  Approval context is unavailable.
                </p>
              <% end %>

              <%= if @approval_context_blocker do %>
                <section
                  id="run-detail-approval-context-error"
                  class="space-y-1 rounded border border-error/40 bg-error/5 p-3"
                >
                  <p id="run-detail-approval-context-error-message" class="text-sm font-semibold text-error">
                    {@approval_context_blocker.message}
                  </p>
                  <p id="run-detail-approval-context-error-detail" class="text-sm text-base-content/80">
                    {@approval_context_blocker.detail}
                  </p>
                  <p id="run-detail-approval-context-remediation" class="text-sm text-base-content/80">
                    {@approval_context_blocker.remediation}
                  </p>
                </section>
              <% end %>

              <div id="run-detail-approval-actions" class="flex gap-2">
                <button id="run-detail-approve-button" type="button" class="btn btn-primary" disabled>
                  Approve
                </button>
                <button id="run-detail-reject-button" type="button" class="btn btn-outline" disabled>
                  Reject
                </button>
              </div>
            </section>
          <% end %>

          <section id="run-detail-timeline" class="space-y-2">
            <h2 class="text-lg font-semibold">Status timeline</h2>

            <%= if @timeline_entries == [] do %>
              <p id="run-detail-timeline-empty" class="text-sm text-base-content/70">
                No status transitions recorded.
              </p>
            <% else %>
              <ol id="run-detail-timeline-list" class="space-y-2">
                <li
                  :for={{entry, index} <- Enum.with_index(@timeline_entries, 1)}
                  id={"run-detail-timeline-entry-#{index}"}
                  class="rounded border border-base-300 bg-base-100 p-3 space-y-1"
                >
                  <p id={"run-detail-timeline-transition-#{index}"} class="text-sm font-medium">
                    {entry.to_status}
                  </p>
                  <p id={"run-detail-timeline-step-#{index}"} class="text-xs text-base-content/80">
                    Step: {entry.current_step}
                  </p>
                  <p id={"run-detail-timeline-at-#{index}"} class="text-xs text-base-content/70">
                    Recorded at: {entry.transitioned_at}
                  </p>
                </li>
              </ol>
            <% end %>
          </section>
        <% else %>
          <section id="run-detail-missing" class="rounded border border-error/40 bg-error/5 p-4 space-y-2">
            <h1 id="run-detail-missing-title" class="text-lg font-semibold">Run not found</h1>
            <p id="run-detail-missing-detail" class="text-sm text-base-content/80">
              Could not find run <span class="font-mono">{@run_id}</span> for this project.
            </p>
          </section>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp assign_missing_run(socket, project_id, run_id) do
    socket
    |> assign(:project_id, project_id)
    |> assign(:run_id, run_id)
    |> assign(:run, nil)
    |> assign(:timeline_entries, [])
    |> assign(:approval_context, nil)
    |> assign(:approval_context_blocker, nil)
  end

  defp timeline_entries(%WorkflowRun{} = run) do
    run
    |> Map.get(:status_transitions, [])
    |> normalize_timeline_entries()
  end

  defp timeline_entries(_run), do: []

  defp approval_context(%WorkflowRun{} = run) do
    step_results =
      run
      |> Map.get(:step_results, %{})
      |> normalize_map()

    context =
      step_results
      |> map_get(:approval_context, "approval_context")
      |> normalize_map()

    diff_summary =
      context
      |> map_get(:diff_summary, "diff_summary")
      |> normalize_optional_string()

    test_summary =
      context
      |> map_get(:test_summary, "test_summary")
      |> normalize_optional_string()

    risk_notes =
      context
      |> map_get(:risk_notes, "risk_notes")
      |> normalize_risk_notes()

    case {diff_summary, test_summary, risk_notes} do
      {nil, nil, []} ->
        nil

      _other ->
        %{
          diff_summary: diff_summary || "Diff summary unavailable.",
          test_summary: test_summary || "Test summary unavailable.",
          risk_notes:
            if(risk_notes == [],
              do: ["Risk notes unavailable. Review changes carefully before approving."],
              else: risk_notes
            )
        }
    end
  end

  defp approval_context(_run), do: nil

  defp approval_context_blocker(%WorkflowRun{} = run) do
    diagnostics =
      run
      |> Map.get(:error, %{})
      |> normalize_map()
      |> Map.get("approval_context_diagnostics", [])
      |> normalize_diagnostics()

    diagnostics
    |> List.last()
    |> normalize_approval_context_diagnostic()
  end

  defp approval_context_blocker(_run), do: nil

  defp awaiting_approval?(status) when is_atom(status), do: status == :awaiting_approval

  defp awaiting_approval?(status) when is_binary(status),
    do: String.trim(status) == "awaiting_approval"

  defp awaiting_approval?(_status), do: false

  defp normalize_timeline_entries(entries) when is_list(entries) do
    Enum.map(entries, fn entry ->
      %{
        to_status:
          entry
          |> map_get(:to_status, "to_status")
          |> normalize_optional_string() || "unknown",
        current_step:
          entry
          |> map_get(:current_step, "current_step")
          |> normalize_optional_string() || "unknown",
        transitioned_at:
          entry
          |> map_get(:transitioned_at, "transitioned_at")
          |> format_transitioned_at()
      }
    end)
  end

  defp normalize_timeline_entries(_entries), do: []

  defp normalize_approval_context_diagnostic(%{} = diagnostic) do
    message =
      diagnostic
      |> map_get(:message, "message")
      |> normalize_optional_string()

    detail =
      diagnostic
      |> map_get(:detail, "detail")
      |> normalize_optional_string()

    remediation =
      diagnostic
      |> map_get(:remediation, "remediation")
      |> normalize_optional_string()

    if is_nil(message) and is_nil(detail) and is_nil(remediation) do
      nil
    else
      %{
        message: message || "Approval context generation failed.",
        detail: detail || "Approval payload generation did not produce complete context.",
        remediation:
          remediation ||
            "Regenerate approval payload data with diff, test, and risk summaries before retrying."
      }
    end
  end

  defp normalize_approval_context_diagnostic(_diagnostic), do: nil

  defp status_label(status) do
    status
    |> normalize_optional_string()
    |> case do
      nil -> "unknown"
      normalized_status -> normalized_status
    end
  end

  defp current_step_label(current_step) do
    current_step
    |> normalize_optional_string()
    |> case do
      nil -> "unknown"
      normalized_step -> normalized_step
    end
  end

  defp format_transitioned_at(%DateTime{} = transitioned_at) do
    DateTime.to_iso8601(transitioned_at)
  end

  defp format_transitioned_at(transitioned_at) when is_binary(transitioned_at) do
    case DateTime.from_iso8601(transitioned_at) do
      {:ok, parsed_transitioned_at, _offset} -> DateTime.to_iso8601(parsed_transitioned_at)
      _other -> transitioned_at
    end
  end

  defp format_transitioned_at(_transitioned_at), do: "unknown"

  defp normalize_map(%{} = map), do: map
  defp normalize_map(_value), do: %{}

  defp normalize_diagnostics(diagnostics) when is_list(diagnostics) do
    Enum.filter(diagnostics, &is_map/1)
  end

  defp normalize_diagnostics(_diagnostics), do: []

  defp normalize_risk_notes(value) when is_list(value) do
    value
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_risk_notes(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil -> []
      risk_note -> [risk_note]
    end
  end

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

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
end
