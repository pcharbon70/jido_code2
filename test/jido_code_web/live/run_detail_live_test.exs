defmodule JidoCodeWeb.RunDetailLiveTest do
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User
  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Projects.Project

  test "renders persisted status transition timeline entries with current step context", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, _session_token} = authenticate_owner_conn("owner@example.com", "owner-password-123")

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
