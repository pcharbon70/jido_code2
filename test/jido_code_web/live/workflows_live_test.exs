defmodule JidoCodeWeb.WorkflowsLiveTest do
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User
  alias JidoCode.Projects.Project

  setup do
    original_workflow_manual_run_launcher =
      Application.get_env(:jido_code, :workflow_manual_run_launcher, :__missing__)

    on_exit(fn ->
      restore_env(:workflow_manual_run_launcher, original_workflow_manual_run_launcher)
    end)

    :ok
  end

  test "creates manual workflow runs with project trigger and input metadata plus run detail route",
       %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-workflows",
        github_full_name: "owner/repo-workflows",
        default_branch: "main",
        settings: %{}
      })

    project_id = project.id

    launch_requests = start_supervised!({Agent, fn -> [] end})

    Application.put_env(:jido_code, :workflow_manual_run_launcher, fn kickoff_request ->
      Agent.update(launch_requests, fn requests -> [kickoff_request | requests] end)
      {:ok, %{run_id: "run-manual-123"}}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workflows", on_error: :warn)

    assert has_element?(view, "#workflows-manual-run-form")
    assert has_element?(view, "#workflows-project-id")
    assert has_element?(view, "#workflows-workflow-name")
    assert has_element?(view, "#workflows-input-task-summary")
    assert has_element?(view, "#workflows-start-run")
    assert has_element?(view, "#workflows-runs-empty-state")

    view
    |> form("#workflows-manual-run-form",
      run: %{
        project_id: project.id,
        workflow_name: "implement_task",
        task_summary: "Ship onboarding copy updates with tests."
      }
    )
    |> render_submit()

    assert has_element?(view, "#workflows-run-feedback-status", "Run creation succeeded.")
    assert has_element?(view, "#workflows-run-feedback-run-id", "run-manual-123")

    assert has_element?(
             view,
             "#workflows-run-feedback-run-link[href='/projects/#{project.id}/runs/run-manual-123']"
           )

    assert has_element?(view, "#workflows-run-id-run-manual-123", "run-manual-123")
    assert has_element?(view, "#workflows-run-workflow-run-manual-123", "implement_task")
    assert has_element?(view, "#workflows-run-project-run-manual-123", "repo-workflows")
    assert has_element?(view, "#workflows-run-trigger-run-manual-123", "/workflows")

    assert has_element?(
             view,
             "#workflows-run-detail-link-run-manual-123[href='/projects/#{project.id}/runs/run-manual-123']"
           )

    refute has_element?(view, "#workflows-runs-empty-state")

    recorded_requests = launch_requests |> Agent.get(&Enum.reverse(&1))

    assert [
             %{
               workflow_name: "implement_task",
               project_id: ^project_id,
               project_defaults: %{
                 default_branch: "main",
                 github_full_name: "owner/repo-workflows"
               },
               trigger: %{
                 source: "workflows",
                 mode: "manual",
                 source_row: %{
                   route: "/workflows",
                   project_id: ^project_id,
                   workflow_name: "implement_task"
                 }
               },
               inputs: %{"task_summary" => "Ship onboarding copy updates with tests."},
               input_metadata: %{
                 "task_summary" => %{required: true, source: "manual_workflows_ui"}
               },
               initiating_actor: %{id: actor_id}
             }
           ] = recorded_requests

    assert is_binary(actor_id)
    refute actor_id == ""
    assert Map.has_key?(hd(recorded_requests).initiating_actor, :email)
  end

  test "missing required inputs return typed validation errors and do not create partial runs", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-validation",
        github_full_name: "owner/repo-validation",
        default_branch: "main",
        settings: %{}
      })

    launcher_invocations = start_supervised!({Agent, fn -> 0 end})

    Application.put_env(:jido_code, :workflow_manual_run_launcher, fn _kickoff_request ->
      Agent.update(launcher_invocations, &(&1 + 1))
      {:ok, %{run_id: "unexpected-run"}}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workflows", on_error: :warn)

    view
    |> form("#workflows-manual-run-form",
      run: %{
        project_id: project.id,
        workflow_name: "implement_task",
        task_summary: ""
      }
    )
    |> render_submit()

    assert has_element?(view, "#workflows-run-feedback-status", "Run creation failed.")

    assert has_element?(
             view,
             "#workflows-run-feedback-error-type",
             "workflow_run_validation_failed"
           )

    assert has_element?(
             view,
             "#workflows-run-feedback-error-detail",
             "required inputs are missing"
           )

    assert has_element?(view, "#workflows-run-feedback-field-errors", "task_summary")
    assert has_element?(view, "#workflows-run-feedback-field-errors", "required")

    refute has_element?(view, "#workflows-run-feedback-run-id")
    assert has_element?(view, "#workflows-runs-empty-state")
    assert Agent.get(launcher_invocations, & &1) == 0
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

  defp restore_env(key, :__missing__) do
    Application.delete_env(:jido_code, key)
  end

  defp restore_env(key, value) do
    Application.put_env(:jido_code, key, value)
  end
end
