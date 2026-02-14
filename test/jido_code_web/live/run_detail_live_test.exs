defmodule JidoCodeWeb.RunDetailLiveTest do
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User
  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Projects.Project

  test "renders persisted status transition timeline entries with current step context", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail",
        github_full_name: "owner/repo-run-detail",
        default_branch: "main",
        settings: %{}
      })

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-detail-123",
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Render transition timeline"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-14 22:00:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-14 22:01:00Z]
      })

    {:ok, _run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-14 22:02:00Z]
      })

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/projects/#{project.id}/runs/run-detail-123", on_error: :warn)

    assert has_element?(view, "#run-detail-title", "Workflow run detail")
    assert has_element?(view, "#run-detail-run-id", "run-detail-123")
    assert has_element?(view, "#run-detail-status", "awaiting_approval")
    assert has_element?(view, "#run-detail-current-step", "approval_gate")

    assert has_element?(view, "#run-detail-timeline-entry-1")
    assert has_element?(view, "#run-detail-timeline-transition-1", "pending")
    assert has_element?(view, "#run-detail-timeline-step-1", "queued")
    assert has_element?(view, "#run-detail-timeline-at-1", "2026-02-14T22:00:00Z")

    assert has_element?(view, "#run-detail-timeline-entry-2")
    assert has_element?(view, "#run-detail-timeline-transition-2", "running")
    assert has_element?(view, "#run-detail-timeline-step-2", "plan_changes")
    assert has_element?(view, "#run-detail-timeline-at-2", "2026-02-14T22:01:00Z")

    assert has_element?(view, "#run-detail-timeline-entry-3")
    assert has_element?(view, "#run-detail-timeline-transition-3", "awaiting_approval")
    assert has_element?(view, "#run-detail-timeline-step-3", "approval_gate")
    assert has_element?(view, "#run-detail-timeline-at-3", "2026-02-14T22:02:00Z")
  end

  test "renders approval payload context and enables explicit approve action", %{
    conn: _conn
  } do
    register_owner("approval-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("approval-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-approval",
        github_full_name: "owner/repo-run-detail-approval",
        default_branch: "main",
        settings: %{}
      })

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-detail-approval-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Render approval payload"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-14 23:00:00Z],
        step_results: %{
          "diff_summary" => "3 files changed (+42/-8).",
          "test_summary" => "mix test: 120 passed, 0 failed.",
          "risk_notes" => [
            "Touches approval gate orchestration.",
            "No credential or secret writes detected."
          ]
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-14 23:01:00Z]
      })

    {:ok, _run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-14 23:02:00Z]
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{run.run_id}",
        on_error: :warn
      )

    assert has_element?(view, "#run-detail-approval-panel")
    assert has_element?(view, "#run-detail-approval-diff-summary", "3 files changed (+42/-8).")

    assert has_element?(
             view,
             "#run-detail-approval-test-summary",
             "mix test: 120 passed, 0 failed."
           )

    assert has_element?(
             view,
             "#run-detail-approval-risk-note-1",
             "Touches approval gate orchestration."
           )

    assert has_element?(
             view,
             "#run-detail-approval-risk-note-2",
             "No credential or secret writes detected."
           )

    assert has_element?(view, "#run-detail-approve-button")
    refute has_element?(view, "#run-detail-approve-button[disabled]")
    assert has_element?(view, "#run-detail-reject-button")
    refute has_element?(view, "#run-detail-reject-button[disabled]")
  end

  test "approves awaiting run, resumes execution, and records timeline audit metadata", %{conn: _conn} do
    register_owner("approval-resume-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("approval-resume-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-approval-resume",
        github_full_name: "owner/repo-run-detail-approval-resume",
        default_branch: "main",
        settings: %{}
      })

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-detail-approval-resume-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Resume on approval"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-14 23:05:00Z],
        step_results: %{
          "diff_summary" => "2 files changed (+9/-1).",
          "test_summary" => "mix test: 18 passed, 0 failed.",
          "risk_notes" => ["Touches approval resume wiring."]
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-14 23:06:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-14 23:07:00Z]
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{run.run_id}",
        on_error: :warn
      )

    render_click(element(view, "#run-detail-approve-button"))

    {:ok, persisted_run} =
      WorkflowRun.get_by_project_and_run_id(%{
        project_id: project.id,
        run_id: run.run_id
      })

    timeline_index = length(persisted_run.status_transitions)

    assert has_element?(view, "#run-detail-status", "running")
    refute has_element?(view, "#run-detail-approval-panel")
    assert has_element?(view, "#run-detail-timeline-transition-#{timeline_index}", "running")
    assert has_element?(view, "#run-detail-timeline-step-#{timeline_index}", "resume_execution")

    assert has_element?(
             view,
             "#run-detail-timeline-approval-audit-#{timeline_index}",
             "approval-resume-owner@example.com"
           )

    assert persisted_run.status == :running
    assert get_in(persisted_run.step_results, ["approval_decision", "decision"]) == "approved"

    assert get_in(persisted_run.step_results, ["approval_decision", "actor", "email"]) ==
             "approval-resume-owner@example.com"
  end

  test "shows typed approval action failure when approval context generation is blocked", %{
    conn: _conn
  } do
    register_owner("approval-failure-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("approval-failure-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-approval-failure",
        github_full_name: "owner/repo-run-detail-approval-failure",
        default_branch: "main",
        settings: %{}
      })

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-detail-approval-failure-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Block approval payload"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-14 23:10:00Z],
        step_results: %{
          "approval_context_generation_error" => "Git diff artifact is missing from prior step output."
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-14 23:11:00Z]
      })

    {:ok, _run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-14 23:12:00Z]
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{run.run_id}",
        on_error: :warn
      )

    assert has_element?(view, "#run-detail-status", "awaiting_approval")

    assert has_element?(
             view,
             "#run-detail-approval-context-missing",
             "Approval context is unavailable."
           )

    assert has_element?(
             view,
             "#run-detail-approval-context-error-message",
             "Approval context generation failed"
           )

    assert has_element?(
             view,
             "#run-detail-approval-context-error-detail",
             "Git diff artifact is missing from prior step output."
           )

    assert has_element?(
             view,
             "#run-detail-approval-context-remediation",
             "Publish diff summary, test summary, and risk notes"
           )

    render_click(element(view, "#run-detail-approve-button"))

    assert has_element?(view, "#run-detail-status", "awaiting_approval")

    assert has_element?(
             view,
             "#run-detail-approval-action-error-type",
             "workflow_run_approval_action_failed"
           )

    assert has_element?(
             view,
             "#run-detail-approval-action-error-detail",
             "Approve action is blocked because approval context generation failed."
           )

    assert has_element?(
             view,
             "#run-detail-approval-action-error-remediation",
             "Regenerate diff summary, test summary, and risk notes before retrying approval."
           )

    {:ok, persisted_run} =
      WorkflowRun.get_by_project_and_run_id(%{
        project_id: project.id,
        run_id: run.run_id
      })

    assert persisted_run.status == :awaiting_approval
    assert has_element?(view, "#run-detail-reject-button")
  end

  test "rejects awaiting run in run detail with rationale metadata and cancelled state", %{
    conn: _conn
  } do
    register_owner("rejection-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("rejection-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-rejection",
        github_full_name: "owner/repo-run-detail-rejection",
        default_branch: "main",
        settings: %{}
      })

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-detail-rejection-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Reject run from run detail"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-14 23:20:00Z],
        step_results: %{
          "diff_summary" => "5 files changed (+64/-20).",
          "test_summary" => "mix test: 77 passed, 0 failed.",
          "risk_notes" => ["Requires a second pass before shipping."]
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-14 23:21:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-14 23:22:00Z]
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{run.run_id}",
        on_error: :warn
      )

    render_submit(element(view, "#run-detail-reject-form"), %{
      "rationale" => "Needs clearer test coverage before merge."
    })

    {:ok, persisted_run} =
      WorkflowRun.get_by_project_and_run_id(%{
        project_id: project.id,
        run_id: run.run_id
      })

    timeline_index = length(persisted_run.status_transitions)

    assert has_element?(view, "#run-detail-status", "cancelled")
    refute has_element?(view, "#run-detail-approval-panel")
    assert has_element?(view, "#run-detail-timeline-transition-#{timeline_index}", "cancelled")
    assert has_element?(view, "#run-detail-timeline-step-#{timeline_index}", "approval_gate")

    assert has_element?(
             view,
             "#run-detail-timeline-approval-audit-#{timeline_index}",
             "rationale=Needs clearer test coverage before merge."
           )

    assert persisted_run.status == :cancelled
    assert get_in(persisted_run.step_results, ["approval_decision", "decision"]) == "rejected"

    assert get_in(persisted_run.step_results, ["approval_decision", "rationale"]) ==
             "Needs clearer test coverage before merge."
  end

  test "shows typed rejection retry guidance when rejection policy routing is invalid", %{
    conn: _conn
  } do
    register_owner("rejection-failure-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("rejection-failure-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-rejection-failure",
        github_full_name: "owner/repo-run-detail-rejection-failure",
        default_branch: "main",
        settings: %{}
      })

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-detail-rejection-failure-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{
          source: "workflows",
          mode: "manual",
          approval_policy: %{
            on_reject: %{
              action: "retry_route",
              retry_step: " "
            }
          }
        },
        inputs: %{"task_summary" => "Reject run with invalid policy"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-14 23:30:00Z],
        step_results: %{
          "diff_summary" => "1 file changed (+2/-1).",
          "test_summary" => "mix test: 12 passed, 0 failed.",
          "risk_notes" => ["Rejection policy validation test."]
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-14 23:31:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-14 23:32:00Z]
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{run.run_id}",
        on_error: :warn
      )

    render_submit(element(view, "#run-detail-reject-form"), %{
      "rationale" => "Routing policy is invalid."
    })

    assert has_element?(view, "#run-detail-status", "awaiting_approval")

    assert has_element?(
             view,
             "#run-detail-approval-action-error-type",
             "workflow_run_approval_action_failed"
           )

    assert has_element?(
             view,
             "#run-detail-approval-action-error-detail",
             "retry route"
           )

    assert has_element?(
             view,
             "#run-detail-approval-action-error-remediation",
             "retry rejection"
           )

    {:ok, persisted_run} =
      WorkflowRun.get_by_project_and_run_id(%{
        project_id: project.id,
        run_id: run.run_id
      })

    assert persisted_run.status == :awaiting_approval
    assert persisted_run.current_step == "approval_gate"
  end

  defp register_owner(email, password) do
    strategy = Info.strategy!(User, :password)

    {:ok, _owner} =
      Strategy.action(
        strategy,
        :register,
        %{
          "email" => email,
          "password" => password,
          "password_confirmation" => password
        },
        context: %{token_type: :sign_in}
      )

    :ok
  end

  defp authenticate_owner_conn(email, password) do
    strategy = Info.strategy!(User, :password)

    {:ok, owner} =
      Strategy.action(
        strategy,
        :sign_in,
        %{"email" => email, "password" => password},
        context: %{token_type: :sign_in}
      )

    token =
      owner
      |> Map.get(:__metadata__, %{})
      |> Map.fetch!(:token)

    auth_response = build_conn() |> get(owner_sign_in_with_token_path(strategy, token))
    assert redirected_to(auth_response, 302) == "/"
    session_token = get_session(auth_response, "user_token")
    assert is_binary(session_token)
    {recycle(auth_response), session_token}
  end

  defp owner_sign_in_with_token_path(strategy, token) do
    strategy_path =
      strategy
      |> Strategy.routes()
      |> Enum.find_value(fn
        {path, :sign_in_with_token} -> path
        _other -> nil
      end)

    path =
      Path.join(
        "/auth",
        String.trim_leading(strategy_path || "/user/password/sign_in_with_token", "/")
      )

    query = URI.encode_query(%{"token" => token})
    "#{path}?#{query}"
  end
end
