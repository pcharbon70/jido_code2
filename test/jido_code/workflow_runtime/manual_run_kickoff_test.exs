defmodule JidoCode.WorkflowRuntime.ManualRunKickoffTest do
  use ExUnit.Case, async: false

  alias JidoCode.WorkflowRuntime.ManualRunKickoff

  setup do
    original_project_loader =
      Application.get_env(:jido_code, :workflow_manual_project_loader, :__missing__)

    original_run_launcher =
      Application.get_env(:jido_code, :workflow_manual_run_launcher, :__missing__)

    on_exit(fn ->
      restore_env(:workflow_manual_project_loader, original_project_loader)
      restore_env(:workflow_manual_run_launcher, original_run_launcher)
    end)

    :ok
  end

  test "kickoff returns run identifier plus project trigger and required input metadata" do
    project_id = "project-123"
    requests = start_supervised!({Agent, fn -> [] end})

    Application.put_env(:jido_code, :workflow_manual_project_loader, fn ->
      {:ok,
       [
         %{
           id: project_id,
           name: "repo-workflows",
           github_full_name: "owner/repo-workflows",
           default_branch: "main"
         }
       ]}
    end)

    Application.put_env(:jido_code, :workflow_manual_run_launcher, fn kickoff_request ->
      Agent.update(requests, fn collected -> [kickoff_request | collected] end)
      {:ok, %{run_id: "run-manual-123"}}
    end)

    {:ok, kickoff_run} =
      ManualRunKickoff.kickoff(
        %{
          "project_id" => project_id,
          "workflow_name" => "implement_task",
          "task_summary" => "Ship onboarding updates."
        },
        %{id: "owner-1", email: "owner@example.com"}
      )

    assert kickoff_run.run_id == "run-manual-123"
    assert kickoff_run.workflow_name == "implement_task"
    assert kickoff_run.project_id == project_id
    assert kickoff_run.detail_path == "/projects/#{project_id}/runs/run-manual-123"

    recorded_requests = requests |> Agent.get(&Enum.reverse(&1))

    assert [
             %{
               workflow_name: "implement_task",
               project_id: ^project_id,
               trigger: %{
                 source: "workflows",
                 mode: "manual",
                 source_row: %{
                   route: "/workflows",
                   project_id: ^project_id,
                   workflow_name: "implement_task"
                 }
               },
               inputs: %{"task_summary" => "Ship onboarding updates."},
               input_metadata: %{
                 "task_summary" => %{required: true, source: "manual_workflows_ui"}
               },
               initiating_actor: %{id: "owner-1", email: "owner@example.com"}
             }
           ] = recorded_requests
  end

  test "missing required inputs returns typed validation error and does not invoke launcher" do
    project_id = "project-456"
    launcher_invocations = start_supervised!({Agent, fn -> 0 end})

    Application.put_env(:jido_code, :workflow_manual_project_loader, fn ->
      {:ok,
       [
         %{
           id: project_id,
           name: "repo-validation",
           github_full_name: "owner/repo-validation",
           default_branch: "main"
         }
       ]}
    end)

    Application.put_env(:jido_code, :workflow_manual_run_launcher, fn _kickoff_request ->
      Agent.update(launcher_invocations, &(&1 + 1))
      {:ok, %{run_id: "unexpected-run"}}
    end)

    assert {:error, kickoff_error} =
             ManualRunKickoff.kickoff(
               %{
                 "project_id" => project_id,
                 "workflow_name" => "implement_task",
                 "task_summary" => ""
               },
               %{id: "owner-1", email: "owner@example.com"}
             )

    assert kickoff_error.error_type == "workflow_run_validation_failed"
    assert kickoff_error.detail =~ "required inputs are missing"

    assert Enum.any?(kickoff_error.field_errors, fn field_error ->
             field_error.field == "task_summary" and field_error.error_type == "required"
           end)

    assert Agent.get(launcher_invocations, & &1) == 0
  end

  defp restore_env(key, :__missing__) do
    Application.delete_env(:jido_code, key)
  end

  defp restore_env(key, value) do
    Application.put_env(:jido_code, key, value)
  end
end
