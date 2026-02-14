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
         |> assign_run(run)
         |> assign(:approval_action_error, nil)
         |> assign(:retry_action_error, nil)}

      {:ok, nil} ->
        {:ok, assign_missing_run(socket, project_id, run_id)}

      {:error, _reason} ->
        {:ok, assign_missing_run(socket, project_id, run_id)}
    end
  end

  @impl true
  def handle_event("approve_run", _params, %{assigns: %{run: %WorkflowRun{} = run}} = socket) do
    case WorkflowRun.approve(run, %{
           actor: approving_actor(socket),
           current_step: "resume_execution"
         }) do
      {:ok, %WorkflowRun{} = approved_run} ->
        {:noreply,
         socket
         |> assign_run(approved_run)
         |> assign(:approval_action_error, nil)
         |> assign(:retry_action_error, nil)}

      {:error, typed_failure} ->
        {:noreply,
         socket
         |> refresh_run_assigns()
         |> assign(:approval_action_error, normalize_approval_action_failure(typed_failure))}
    end
  end

  @impl true
  def handle_event("approve_run", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("reject_run", params, %{assigns: %{run: %WorkflowRun{} = run}} = socket) do
    rationale =
      params
      |> map_get(:rationale, "rationale")
      |> normalize_optional_string()

    case WorkflowRun.reject(run, %{
           actor: approving_actor(socket),
           rationale: rationale
         }) do
      {:ok, %WorkflowRun{} = rejected_run} ->
        {:noreply,
         socket
         |> assign_run(rejected_run)
         |> assign(:approval_action_error, nil)
         |> assign(:retry_action_error, nil)}

      {:error, typed_failure} ->
        {:noreply,
         socket
         |> refresh_run_assigns()
         |> assign(:approval_action_error, normalize_approval_action_failure(typed_failure))}
    end
  end

  @impl true
  def handle_event("reject_run", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("retry_run", _params, %{assigns: %{run: %WorkflowRun{} = run}} = socket) do
    case WorkflowRun.retry(run, %{actor: approving_actor(socket)}) do
      {:ok, %WorkflowRun{} = retried_run} ->
        {:noreply,
         socket
         |> assign(:retry_action_error, nil)
         |> assign(:approval_action_error, nil)
         |> put_flash(:info, "Full-run retry started as #{retried_run.run_id}.")
         |> push_navigate(to: ~p"/projects/#{socket.assigns.project_id}/runs/#{retried_run.run_id}")}

      {:error, typed_failure} ->
        {:noreply,
         socket
         |> refresh_run_assigns()
         |> assign(:retry_action_error, normalize_retry_action_failure(typed_failure))}
    end
  end

  @impl true
  def handle_event("retry_run", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("retry_step", _params, %{assigns: %{run: %WorkflowRun{} = run}} = socket) do
    case WorkflowRun.retry_step(run, %{actor: approving_actor(socket)}) do
      {:ok, %WorkflowRun{} = retried_run} ->
        {:noreply,
         socket
         |> assign(:retry_action_error, nil)
         |> assign(:approval_action_error, nil)
         |> put_flash(
           :info,
           "Step-level retry started at #{retried_run.current_step} as #{retried_run.run_id}."
         )
         |> push_navigate(to: ~p"/projects/#{socket.assigns.project_id}/runs/#{retried_run.run_id}")}

      {:error, typed_failure} ->
        {:noreply,
         socket
         |> refresh_run_assigns()
         |> assign(:retry_action_error, normalize_retry_action_failure(typed_failure))}
    end
  end

  @impl true
  def handle_event("retry_step", _params, socket), do: {:noreply, socket}

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
            <p id="run-detail-retry-attempt" class="text-sm">
              Attempt: {Map.get(@run, :retry_attempt, 1)}
            </p>
            <p
              :if={normalize_optional_string(Map.get(@run, :retry_of_run_id))}
              id="run-detail-retry-parent-run"
              class="text-sm"
            >
              Retry parent: <span class="font-mono">{Map.get(@run, :retry_of_run_id)}</span>
            </p>
          </section>

          <%= if awaiting_approval?(@run.status) do %>
            <section id="run-detail-approval-panel" class="space-y-3 rounded border border-base-300 bg-base-100 p-4">
              <h2 class="text-lg font-semibold">Approval request payload</h2>
              <p id="run-detail-approval-panel-note" class="text-sm text-base-content/80">
                Review this context before approving.
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

              <div id="run-detail-approval-actions" class="space-y-3">
                <button
                  id="run-detail-approve-button"
                  type="button"
                  class="btn btn-primary"
                  phx-click="approve_run"
                >
                  Approve
                </button>

                <form id="run-detail-reject-form" phx-submit="reject_run" class="space-y-2">
                  <.input
                    id="run-detail-reject-rationale"
                    type="textarea"
                    name="rationale"
                    label="Rejection rationale (optional)"
                    value=""
                  />
                  <button id="run-detail-reject-button" type="submit" class="btn btn-outline">
                    Reject
                  </button>
                </form>
              </div>

              <%= if @approval_action_error do %>
                <section
                  id="run-detail-approval-action-error"
                  class="space-y-1 rounded border border-error/40 bg-error/5 p-3"
                >
                  <p id="run-detail-approval-action-error-type" class="text-sm font-semibold text-error">
                    Typed action failure: {@approval_action_error.error_type}
                  </p>
                  <p id="run-detail-approval-action-error-detail" class="text-sm text-base-content/80">
                    {@approval_action_error.detail}
                  </p>
                  <p id="run-detail-approval-action-error-remediation" class="text-sm text-base-content/80">
                    {@approval_action_error.remediation}
                  </p>
                </section>
              <% end %>
            </section>
          <% end %>

          <%= if full_run_retry_available?(@run.status) do %>
            <section id="run-detail-retry-panel" class="space-y-3 rounded border border-base-300 bg-base-100 p-4">
              <h2 class="text-lg font-semibold">Retry run</h2>
              <p id="run-detail-retry-note" class="text-sm text-base-content/80">
                Starts a full-run retry attempt and preserves failure lineage for artifact and reason lookup.
              </p>
              <button
                id="run-detail-retry-button"
                type="button"
                class="btn btn-outline"
                phx-click="retry_run"
              >
                Retry full run
              </button>

              <%= if @step_retry_state.available do %>
                <section id="run-detail-step-retry-panel" class="space-y-2 rounded border border-base-300 p-3">
                  <p id="run-detail-step-retry-note" class="text-sm text-base-content/80">
                    Restarts retry at contract step <span class="font-mono">{@step_retry_state.retry_step}</span>
                    while preserving prior failure lineage.
                  </p>
                  <button
                    id="run-detail-step-retry-button"
                    type="button"
                    class="btn btn-outline"
                    phx-click="retry_step"
                  >
                    Retry from contract step
                  </button>
                </section>
              <% else %>
                <section
                  :if={@step_retry_state.guidance}
                  id="run-detail-step-retry-guidance"
                  class="space-y-1 rounded border border-base-300/70 bg-base-200/40 p-3"
                >
                  <p id="run-detail-step-retry-guidance-detail" class="text-sm text-base-content/80">
                    {@step_retry_state.guidance.detail}
                  </p>
                  <p id="run-detail-step-retry-guidance-remediation" class="text-sm text-base-content/80">
                    {@step_retry_state.guidance.remediation}
                  </p>
                </section>
              <% end %>

              <%= if @retry_action_error do %>
                <section
                  id="run-detail-retry-action-error"
                  class="space-y-1 rounded border border-error/40 bg-error/5 p-3"
                >
                  <p id="run-detail-retry-action-error-type" class="text-sm font-semibold text-error">
                    Typed action failure: {@retry_action_error.error_type}
                  </p>
                  <p id="run-detail-retry-action-error-detail" class="text-sm text-base-content/80">
                    {@retry_action_error.detail}
                  </p>
                  <p id="run-detail-retry-action-error-remediation" class="text-sm text-base-content/80">
                    {@retry_action_error.remediation}
                  </p>
                </section>
              <% end %>
            </section>
          <% end %>

          <%= if @retry_lineage_entries != [] do %>
            <section id="run-detail-retry-lineage" class="space-y-2">
              <h2 class="text-lg font-semibold">Retry lineage</h2>
              <ol id="run-detail-retry-lineage-list" class="space-y-2">
                <li
                  :for={{entry, index} <- Enum.with_index(@retry_lineage_entries, 1)}
                  id={"run-detail-retry-lineage-entry-#{index}"}
                  class="rounded border border-base-300 bg-base-100 p-3 space-y-1"
                >
                  <p id={"run-detail-retry-lineage-run-id-#{index}"} class="text-sm">
                    Prior run: <span class="font-mono">{entry.run_id}</span>
                  </p>
                  <p id={"run-detail-retry-lineage-status-#{index}"} class="text-xs text-base-content/80">
                    Status: {entry.status} (attempt {entry.retry_attempt})
                  </p>
                  <p id={"run-detail-retry-lineage-reason-type-#{index}"} class="text-xs text-base-content/80">
                    Typed reason: {entry.reason_type}
                  </p>
                  <p id={"run-detail-retry-lineage-detail-#{index}"} class="text-xs text-base-content/80">
                    {entry.detail}
                  </p>
                  <p id={"run-detail-retry-lineage-artifact-count-#{index}"} class="text-xs text-base-content/80">
                    Preserved artifact keys: {entry.artifact_count}
                  </p>
                </li>
              </ol>
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
                  <%= if entry.approval_audit do %>
                    <p id={"run-detail-timeline-approval-audit-#{index}"} class="text-xs text-base-content/80">
                      Approval audit: {entry.approval_audit}
                    </p>
                  <% end %>
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
    |> assign(:retry_lineage_entries, [])
    |> assign(:approval_context, nil)
    |> assign(:approval_context_blocker, nil)
    |> assign(:step_retry_state, step_retry_state(nil))
    |> assign(:approval_action_error, nil)
    |> assign(:retry_action_error, nil)
  end

  defp timeline_entries(%WorkflowRun{} = run) do
    run
    |> Map.get(:status_transitions, [])
    |> normalize_timeline_entries()
  end

  defp timeline_entries(_run), do: []

  defp assign_run(socket, %WorkflowRun{} = run) do
    socket
    |> assign(:run, run)
    |> assign(:timeline_entries, timeline_entries(run))
    |> assign(:retry_lineage_entries, retry_lineage_entries(run))
    |> assign(:approval_context, approval_context(run))
    |> assign(:approval_context_blocker, approval_context_blocker(run))
    |> assign(:step_retry_state, step_retry_state(run))
  end

  defp refresh_run_assigns(%{assigns: %{project_id: project_id, run_id: run_id}} = socket) do
    case WorkflowRun.get_by_project_and_run_id(%{project_id: project_id, run_id: run_id}) do
      {:ok, %WorkflowRun{} = run} -> assign_run(socket, run)
      _other -> assign_missing_run(socket, project_id, run_id)
    end
  end

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

  defp retry_lineage_entries(%WorkflowRun{} = run) do
    run
    |> Map.get(:retry_lineage, [])
    |> normalize_retry_lineage_entries()
  end

  defp retry_lineage_entries(_run), do: []

  defp normalize_retry_lineage_entries(entries) when is_list(entries) do
    Enum.map(entries, fn entry ->
      typed_failure =
        entry
        |> map_get(:typed_failure, "typed_failure", %{})
        |> normalize_map()

      failure_artifacts =
        entry
        |> map_get(:failure_artifacts, "failure_artifacts", %{})
        |> normalize_map()

      %{
        run_id:
          entry
          |> map_get(:run_id, "run_id")
          |> normalize_optional_string() || "unknown",
        status:
          entry
          |> map_get(:status, "status")
          |> normalize_optional_string() || "unknown",
        retry_attempt:
          entry
          |> map_get(:retry_attempt, "retry_attempt")
          |> normalize_optional_integer() || 1,
        reason_type:
          typed_failure
          |> map_get(:reason_type, "reason_type")
          |> normalize_optional_string() || "unknown",
        detail:
          typed_failure
          |> map_get(:detail, "detail")
          |> normalize_optional_string() || "Prior failure details were not captured.",
        artifact_count: map_size(failure_artifacts)
      }
    end)
  end

  defp normalize_retry_lineage_entries(_entries), do: []

  defp step_retry_state(%WorkflowRun{} = run) do
    case WorkflowRun.step_retry_contract(run) do
      {:ok, step_retry_contract} ->
        %{
          available: true,
          retry_step:
            step_retry_contract
            |> map_get(:retry_step, "retry_step")
            |> normalize_optional_string(),
          guidance: nil
        }

      {:error, typed_failure} ->
        %{
          available: false,
          retry_step: nil,
          guidance: normalize_retry_action_failure(typed_failure)
        }
    end
  end

  defp step_retry_state(_run) do
    %{
      available: false,
      retry_step: nil,
      guidance: nil
    }
  end

  defp full_run_retry_available?(status) when is_atom(status), do: status in [:failed, :cancelled]

  defp full_run_retry_available?(status) when is_binary(status) do
    case String.trim(status) do
      "failed" -> true
      "cancelled" -> true
      _other -> false
    end
  end

  defp full_run_retry_available?(_status), do: false

  defp awaiting_approval?(status) when is_atom(status), do: status == :awaiting_approval

  defp awaiting_approval?(status) when is_binary(status),
    do: String.trim(status) == "awaiting_approval"

  defp awaiting_approval?(_status), do: false

  defp normalize_timeline_entries(entries) when is_list(entries) do
    Enum.map(entries, fn entry ->
      approval_audit = normalize_timeline_approval_audit(entry)

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
          |> format_transitioned_at(),
        approval_audit: approval_audit
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

  defp normalize_approval_action_failure(typed_failure) when is_map(typed_failure) do
    error_type =
      typed_failure
      |> map_get(:error_type, "error_type")
      |> normalize_optional_string()

    detail =
      typed_failure
      |> map_get(:detail, "detail")
      |> normalize_optional_string()

    remediation =
      typed_failure
      |> map_get(:remediation, "remediation")
      |> normalize_optional_string()

    %{
      error_type: error_type || "workflow_run_approval_action_failed",
      detail: detail || "Approval action failed and run remains blocked.",
      remediation: remediation || "Review run state and retry from run detail."
    }
  end

  defp normalize_approval_action_failure(_typed_failure) do
    %{
      error_type: "workflow_run_approval_action_failed",
      detail: "Approval action failed and run remains blocked.",
      remediation: "Review run state and retry from run detail."
    }
  end

  defp normalize_retry_action_failure(typed_failure) when is_map(typed_failure) do
    error_type =
      typed_failure
      |> map_get(:error_type, "error_type")
      |> normalize_optional_string()

    detail =
      typed_failure
      |> map_get(:detail, "detail")
      |> normalize_optional_string()

    remediation =
      typed_failure
      |> map_get(:remediation, "remediation")
      |> normalize_optional_string()

    %{
      error_type: error_type || "workflow_run_retry_action_failed",
      detail: detail || "Retry action failed and no new attempt was created.",
      remediation: remediation || "Review workflow retry policy and retry from run detail."
    }
  end

  defp normalize_retry_action_failure(_typed_failure) do
    %{
      error_type: "workflow_run_retry_action_failed",
      detail: "Retry action failed and no new attempt was created.",
      remediation: "Review workflow retry policy and retry from run detail."
    }
  end

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

  defp normalize_timeline_approval_audit(entry) when is_map(entry) do
    decision =
      entry
      |> map_get(:metadata, "metadata", %{})
      |> map_get(:approval_decision, "approval_decision", %{})
      |> map_get(:decision, "decision")
      |> normalize_optional_string()

    actor =
      entry
      |> map_get(:metadata, "metadata", %{})
      |> map_get(:approval_decision, "approval_decision", %{})
      |> map_get(:actor, "actor", %{})

    actor_id = actor |> map_get(:id, "id") |> normalize_optional_string()
    actor_email = actor |> map_get(:email, "email") |> normalize_optional_string()

    timestamp =
      entry
      |> map_get(:metadata, "metadata", %{})
      |> map_get(:approval_decision, "approval_decision", %{})
      |> map_get(:timestamp, "timestamp")
      |> normalize_optional_string()

    rationale =
      entry
      |> map_get(:metadata, "metadata", %{})
      |> map_get(:approval_decision, "approval_decision", %{})
      |> map_get(:rationale, "rationale")
      |> normalize_optional_string()

    actor_label = actor_email || actor_id

    parts =
      [
        if(decision, do: "decision=#{decision}"),
        if(actor_label, do: "actor=#{actor_label}"),
        if(timestamp, do: "at=#{format_transitioned_at(timestamp)}"),
        if(rationale, do: "rationale=#{rationale}")
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> nil
      audit_parts -> Enum.join(audit_parts, " ")
    end
  end

  defp normalize_timeline_approval_audit(_entry), do: nil

  defp approving_actor(socket) do
    socket.assigns
    |> Map.get(:current_user)
    |> case do
      %{} = user ->
        %{
          id: user |> Map.get(:id) |> normalize_optional_string() || "unknown",
          email: user |> Map.get(:email) |> normalize_optional_string()
        }

      _other ->
        %{id: "unknown", email: nil}
    end
  end

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

  defp normalize_optional_string(%Ash.CiString{} = value),
    do: value |> to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(value) when is_float(value), do: :erlang.float_to_binary(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_optional_integer(value) when is_integer(value), do: value

  defp normalize_optional_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> parsed
      _other -> nil
    end
  end

  defp normalize_optional_integer(_value), do: nil
end
