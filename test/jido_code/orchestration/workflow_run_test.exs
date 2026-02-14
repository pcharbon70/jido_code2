defmodule JidoCode.Orchestration.WorkflowRunTest do
  use JidoCode.DataCase, async: false

  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Projects.Project

  test "persists allowed lifecycle transitions with timestamps and current step context" do
    {:ok, project} = create_project("owner/repo-lifecycle")

    started_at = ~U[2026-02-14 20:00:00Z]
    running_at = ~U[2026-02-14 20:01:00Z]
    awaiting_approval_at = ~U[2026-02-14 20:02:00Z]
    resumed_at = ~U[2026-02-14 20:03:00Z]
    completed_at = ~U[2026-02-14 20:04:00Z]

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-lifecycle-123",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Persist lifecycle transitions"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: started_at
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: running_at
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: awaiting_approval_at
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "apply_feedback",
        transitioned_at: resumed_at
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :completed,
        current_step: "publish_pr",
        transitioned_at: completed_at
      })

    {:ok, persisted_run} =
      WorkflowRun.get_by_project_and_run_id(%{
        project_id: project.id,
        run_id: run.run_id
      })

    assert persisted_run.status == :completed
    assert persisted_run.current_step == "publish_pr"
    assert DateTime.compare(DateTime.truncate(persisted_run.started_at, :second), started_at) == :eq
    assert DateTime.compare(DateTime.truncate(persisted_run.completed_at, :second), completed_at) == :eq

    assert [
             %{
               "from_status" => nil,
               "to_status" => "pending",
               "current_step" => "queued",
               "transitioned_at" => "2026-02-14T20:00:00Z"
             },
             %{
               "from_status" => "pending",
               "to_status" => "running",
               "current_step" => "plan_changes",
               "transitioned_at" => "2026-02-14T20:01:00Z"
             },
             %{
               "from_status" => "running",
               "to_status" => "awaiting_approval",
               "current_step" => "approval_gate",
               "transitioned_at" => "2026-02-14T20:02:00Z"
             },
             %{
               "from_status" => "awaiting_approval",
               "to_status" => "running",
               "current_step" => "apply_feedback",
               "transitioned_at" => "2026-02-14T20:03:00Z"
             },
             %{
               "from_status" => "running",
               "to_status" => "completed",
               "current_step" => "publish_pr",
               "transitioned_at" => "2026-02-14T20:04:00Z"
             }
           ] = persisted_run.status_transitions
  end

  test "rejects invalid transitions and leaves persisted run state unchanged" do
    {:ok, project} = create_project("owner/repo-invalid-transition")

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-invalid-123",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Attempt invalid transition"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-14 21:00:00Z]
      })

    assert {:error, error} =
             WorkflowRun.transition_status(run, %{
               to_status: :completed,
               current_step: "publish_pr",
               transitioned_at: ~U[2026-02-14 21:01:00Z]
             })

    assert Exception.message(error) =~ "invalid lifecycle transition from pending to completed"

    {:ok, persisted_run} =
      WorkflowRun.get_by_project_and_run_id(%{
        project_id: project.id,
        run_id: run.run_id
      })

    assert persisted_run.status == :pending
    assert persisted_run.current_step == "queued"
    assert persisted_run.completed_at == nil

    assert [
             %{
               "from_status" => nil,
               "to_status" => "pending",
               "current_step" => "queued",
               "transitioned_at" => "2026-02-14T21:00:00Z"
             }
           ] = persisted_run.status_transitions
  end

  defp create_project(github_full_name) do
    Project.create(%{
      name: github_full_name,
      github_full_name: github_full_name,
      default_branch: "main",
      settings: %{}
    })
  end
end
