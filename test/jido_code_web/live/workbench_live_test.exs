defmodule JidoCodeWeb.WorkbenchLiveTest do
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User
  alias JidoCode.Projects.Project

  setup do
    original_workbench_loader = Application.get_env(:jido_code, :workbench_inventory_loader, :__missing__)
    original_system_config_loader = Application.get_env(:jido_code, :system_config_loader, :__missing__)

    Application.put_env(:jido_code, :system_config_loader, fn ->
      {:ok,
       %{
         onboarding_completed: true,
         onboarding_step: 8,
         onboarding_state: %{},
         default_environment: :sprite,
         workspace_root: nil
       }}
    end)

    on_exit(fn ->
      restore_env(:workbench_inventory_loader, original_workbench_loader)
      restore_env(:system_config_loader, original_system_config_loader)
    end)

    :ok
  end

  test "renders cross-project workbench inventory rows with issue and PR counts plus activity summary", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, _session_token} = authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project_one} =
      Project.create(%{
        name: "repo-one",
        github_full_name: "owner/repo-one",
        default_branch: "main",
        settings: %{
          "inventory" => %{
            "open_issue_count" => 12,
            "open_pr_count" => 3,
            "recent_activity_summary" => "Triaged issues and queued follow-up in the last hour."
          }
        }
      })

    {:ok, project_two} =
      Project.create(%{
        name: "repo-two",
        github_full_name: "owner/repo-two",
        default_branch: "main",
        settings: %{
          "github" => %{
            "open_issues_count" => "4",
            "open_pull_requests_count" => 1,
            "pushed_at" => "2026-02-13T16:00:00Z"
          }
        }
      })

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(view, "#workbench-project-table")
    assert has_element?(view, "#workbench-project-name-#{project_one.id}", "owner/repo-one")
    assert has_element?(view, "#workbench-project-open-issues-#{project_one.id}", "12")
    assert has_element?(view, "#workbench-project-open-prs-#{project_one.id}", "3")
    assert has_element?(view, "#workbench-project-issues-github-link-#{project_one.id}")
    assert has_element?(view, "#workbench-project-issues-project-link-#{project_one.id}")
    assert has_element?(view, "#workbench-project-prs-github-link-#{project_one.id}")
    assert has_element?(view, "#workbench-project-prs-project-link-#{project_one.id}")

    assert has_element?(
             view,
             "#workbench-project-issues-github-link-#{project_one.id}[href='https://github.com/owner/repo-one/issues']"
           )

    assert has_element?(
             view,
             "#workbench-project-prs-github-link-#{project_one.id}[href='https://github.com/owner/repo-one/pulls']"
           )

    assert has_element?(
             view,
             "#workbench-project-issues-project-link-#{project_one.id}[href='/projects/#{project_one.id}']"
           )

    assert has_element?(
             view,
             "#workbench-project-prs-project-link-#{project_one.id}[href='/projects/#{project_one.id}']"
           )

    assert has_element?(
             view,
             "#workbench-project-recent-activity-#{project_one.id}",
             "Triaged issues and queued follow-up in the last hour."
           )

    assert has_element?(view, "#workbench-project-name-#{project_two.id}", "owner/repo-two")
    assert has_element?(view, "#workbench-project-open-issues-#{project_two.id}", "4")
    assert has_element?(view, "#workbench-project-open-prs-#{project_two.id}", "1")
    assert has_element?(view, "#workbench-project-issues-github-link-#{project_two.id}")
    assert has_element?(view, "#workbench-project-issues-project-link-#{project_two.id}")
    assert has_element?(view, "#workbench-project-prs-github-link-#{project_two.id}")
    assert has_element?(view, "#workbench-project-prs-project-link-#{project_two.id}")

    assert has_element?(
             view,
             "#workbench-project-issues-github-link-#{project_two.id}[href='https://github.com/owner/repo-two/issues']"
           )

    assert has_element?(
             view,
             "#workbench-project-prs-github-link-#{project_two.id}[href='https://github.com/owner/repo-two/pulls']"
           )

    assert has_element?(
             view,
             "#workbench-project-issues-project-link-#{project_two.id}[href='/projects/#{project_two.id}']"
           )

    assert has_element?(
             view,
             "#workbench-project-prs-project-link-#{project_two.id}[href='/projects/#{project_two.id}']"
           )

    assert has_element?(view, "#workbench-project-recent-activity-#{project_two.id}")

    refute has_element?(view, "#workbench-stale-warning")
  end

  test "shows stale-state warning and recovery actions when workbench data fetch fails", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, _session_token} = authenticate_owner_conn("owner@example.com", "owner-password-123")

    # LiveView mounts twice (disconnected + connected), so fail both initial loads
    # and recover on explicit retry.
    loader_state = start_supervised!({Agent, fn -> 0 end})

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      Agent.get_and_update(loader_state, fn
        call_count when call_count < 2 ->
          warning = %{
            error_type: "workbench_data_fetch_failed",
            detail: "GitHub inventory sync timed out and current counts may be stale.",
            remediation: "Retry workbench fetch and review setup diagnostics if the issue persists."
          }

          {{:error, warning}, call_count + 1}

        call_count ->
          rows = [
            %{
              id: "owner-repo-recovered",
              name: "repo-recovered",
              github_full_name: "owner/repo-recovered",
              open_issue_count: 7,
              open_pr_count: 2,
              recent_activity_summary: "Recovery refresh completed."
            }
          ]

          {{:ok, rows, nil}, call_count + 1}
      end)
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(view, "#workbench-stale-warning")
    assert has_element?(view, "#workbench-stale-warning-type", "workbench_data_fetch_failed")
    assert has_element?(view, "#workbench-stale-warning-detail", "counts may be stale")
    assert has_element?(view, "#workbench-stale-warning-remediation", "Retry workbench fetch")
    assert has_element?(view, "#workbench-retry-fetch")
    assert has_element?(view, "#workbench-open-setup-recovery")

    view
    |> element("#workbench-retry-fetch")
    |> render_click()

    refute has_element?(view, "#workbench-stale-warning")
    assert has_element?(view, "#workbench-project-name-owner-repo-recovered", "owner/repo-recovered")
    assert has_element?(view, "#workbench-project-open-issues-owner-repo-recovered", "7")
    assert has_element?(view, "#workbench-project-open-prs-owner-repo-recovered", "2")

    assert has_element?(
             view,
             "#workbench-project-recent-activity-owner-repo-recovered",
             "Recovery refresh completed."
           )
  end

  test "shows disabled link states with explanations when row link targets are unavailable", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, _session_token} = authenticate_owner_conn("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: "",
           name: "repo-with-missing-links",
           github_full_name: "",
           open_issue_count: 2,
           open_pr_count: 1,
           recent_activity_summary: "No metadata available for links."
         }
       ], nil}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(
             view,
             "[id^='workbench-project-issues-github-disabled-workbench-row-'][aria-disabled='true']",
             "GitHub issues"
           )

    assert has_element?(
             view,
             "[id^='workbench-project-issues-github-disabled-reason-workbench-row-']",
             "GitHub repository URL is unavailable for this row."
           )

    assert has_element?(
             view,
             "[id^='workbench-project-prs-github-disabled-workbench-row-'][aria-disabled='true']",
             "GitHub PRs"
           )

    assert has_element?(
             view,
             "[id^='workbench-project-prs-github-disabled-reason-workbench-row-']",
             "GitHub repository URL is unavailable for this row."
           )

    assert has_element?(
             view,
             "[id^='workbench-project-issues-project-disabled-workbench-row-'][aria-disabled='true']",
             "Project detail"
           )

    assert has_element?(
             view,
             "[id^='workbench-project-issues-project-disabled-reason-workbench-row-']",
             "Project detail link is unavailable for this row."
           )

    assert has_element?(
             view,
             "[id^='workbench-project-prs-project-disabled-workbench-row-'][aria-disabled='true']",
             "Project detail"
           )

    assert has_element?(
             view,
             "[id^='workbench-project-prs-project-disabled-reason-workbench-row-']",
             "Project detail link is unavailable for this row."
           )

    refute has_element?(view, "[id^='workbench-project-issues-github-link-workbench-row-']")
    refute has_element?(view, "[id^='workbench-project-prs-github-link-workbench-row-']")
    refute has_element?(view, "[id^='workbench-project-issues-project-link-workbench-row-']")
    refute has_element?(view, "[id^='workbench-project-prs-project-link-workbench-row-']")
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

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
