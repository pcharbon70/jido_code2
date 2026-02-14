defmodule JidoCodeWeb.WorkbenchLiveTest do
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User
  alias JidoCode.Projects.Project

  setup do
    original_workbench_loader =
      Application.get_env(:jido_code, :workbench_inventory_loader, :__missing__)

    original_system_config_loader =
      Application.get_env(:jido_code, :system_config_loader, :__missing__)

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

  test "renders cross-project workbench inventory rows with issue and PR counts plus activity summary",
       %{
         conn: _conn
       } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

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

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

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

    assert has_element?(
             view,
             "#workbench-project-name-owner-repo-recovered",
             "owner/repo-recovered"
           )

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

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

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

  test "applies project, state, and freshness filters without route changes", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    now = DateTime.utc_now()

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: "owner-repo-alpha",
           name: "repo-alpha",
           github_full_name: "owner/repo-alpha",
           open_issue_count: 5,
           open_pr_count: 0,
           recent_activity_summary: "Alpha summary",
           recent_activity_at: DateTime.add(now, -45 * 24 * 60 * 60, :second) |> DateTime.to_iso8601()
         },
         %{
           id: "owner-repo-beta",
           name: "repo-beta",
           github_full_name: "owner/repo-beta",
           open_issue_count: 0,
           open_pr_count: 4,
           recent_activity_summary: "Beta summary",
           recent_activity_at: DateTime.add(now, -2 * 60 * 60, :second) |> DateTime.to_iso8601()
         },
         %{
           id: "owner-repo-gamma",
           name: "repo-gamma",
           github_full_name: "owner/repo-gamma",
           open_issue_count: 2,
           open_pr_count: 1,
           recent_activity_summary: "Gamma summary",
           recent_activity_at: DateTime.add(now, -10 * 24 * 60 * 60, :second) |> DateTime.to_iso8601()
         }
       ], nil}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(view, "#workbench-filters-form")
    assert has_element?(view, "#workbench-project-name-owner-repo-alpha", "owner/repo-alpha")
    assert has_element?(view, "#workbench-project-name-owner-repo-beta", "owner/repo-beta")
    assert has_element?(view, "#workbench-project-name-owner-repo-gamma", "owner/repo-gamma")
    assert has_element?(view, "#workbench-filter-results-count", "Showing 3 of 3")

    apply_workbench_filters(view, %{"project_id" => "owner-repo-beta"})

    assert has_element?(view, "#workbench-filters-form")
    assert has_element?(view, "#workbench-project-name-owner-repo-beta", "owner/repo-beta")
    refute has_element?(view, "#workbench-project-name-owner-repo-alpha")
    refute has_element?(view, "#workbench-project-name-owner-repo-gamma")
    assert has_element?(view, "#workbench-filter-chip-project", "owner/repo-beta")
    assert has_element?(view, "#workbench-filter-results-count", "Showing 1 of 3")

    apply_workbench_filters(view, %{"work_state" => "issues_open"})

    assert has_element?(view, "#workbench-filters-form")
    assert has_element?(view, "#workbench-project-name-owner-repo-alpha", "owner/repo-alpha")
    refute has_element?(view, "#workbench-project-name-owner-repo-beta")
    assert has_element?(view, "#workbench-project-name-owner-repo-gamma", "owner/repo-gamma")
    assert has_element?(view, "#workbench-filter-chip-work-state", "Issues open")
    assert has_element?(view, "#workbench-filter-results-count", "Showing 2 of 3")

    apply_workbench_filters(view, %{"freshness_window" => "stale_30d"})

    assert has_element?(view, "#workbench-filters-form")
    assert has_element?(view, "#workbench-project-name-owner-repo-alpha", "owner/repo-alpha")
    refute has_element?(view, "#workbench-project-name-owner-repo-beta")
    refute has_element?(view, "#workbench-project-name-owner-repo-gamma")
    assert has_element?(view, "#workbench-filter-chip-freshness-window", "Stale for 30+ days")
    assert has_element?(view, "#workbench-filter-results-count", "Showing 1 of 3")
  end

  test "supports backlog and recent activity sort ordering with deterministic results", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    now = DateTime.utc_now()

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: "owner-repo-alpha",
           name: "repo-alpha",
           github_full_name: "owner/repo-alpha",
           open_issue_count: 2,
           open_pr_count: 1,
           recent_activity_summary: "Alpha summary",
           recent_activity_at: DateTime.add(now, -2 * 60 * 60, :second) |> DateTime.to_iso8601()
         },
         %{
           id: "owner-repo-beta",
           name: "repo-beta",
           github_full_name: "owner/repo-beta",
           open_issue_count: 5,
           open_pr_count: 4,
           recent_activity_summary: "Beta summary",
           recent_activity_at: DateTime.add(now, -9 * 60 * 60, :second) |> DateTime.to_iso8601()
         },
         %{
           id: "owner-repo-gamma",
           name: "repo-gamma",
           github_full_name: "owner/repo-gamma",
           open_issue_count: 1,
           open_pr_count: 0,
           recent_activity_summary: "Gamma summary",
           recent_activity_at: DateTime.add(now, -60 * 60, :second) |> DateTime.to_iso8601()
         }
       ], nil}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(
             view,
             "#workbench-filter-sort-order option[value='backlog_desc']",
             "Backlog size (highest first)"
           )

    assert has_element?(
             view,
             "#workbench-filter-sort-order option[value='recent_activity_desc']",
             "Recent activity (most recent first)"
           )

    apply_workbench_filters(view, %{"sort_order" => "backlog_desc"})

    assert_project_row_order(view, ["owner-repo-beta", "owner-repo-alpha", "owner-repo-gamma"])

    apply_workbench_filters(view, %{"sort_order" => "backlog_desc"})

    assert_project_row_order(view, ["owner-repo-beta", "owner-repo-alpha", "owner-repo-gamma"])

    apply_workbench_filters(view, %{"sort_order" => "recent_activity_desc"})

    assert_project_row_order(view, ["owner-repo-gamma", "owner-repo-alpha", "owner-repo-beta"])
    assert has_element?(view, "#workbench-filter-chip-sort-order", "Recent activity (most recent first)")
  end

  test "keeps selected sort order after retry refresh events", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    stale_warning = %{
      error_type: "workbench_refresh_state_warning",
      detail: "Refresh is available.",
      remediation: "Use retry to refresh data."
    }

    loader_state = start_supervised!({Agent, fn -> 0 end})

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      Agent.get_and_update(loader_state, fn call_count ->
        rows =
          if call_count < 2 do
            [
              %{
                id: "owner-repo-alpha",
                name: "repo-alpha",
                github_full_name: "owner/repo-alpha",
                open_issue_count: 5,
                open_pr_count: 0,
                recent_activity_summary: "Alpha summary"
              },
              %{
                id: "owner-repo-beta",
                name: "repo-beta",
                github_full_name: "owner/repo-beta",
                open_issue_count: 2,
                open_pr_count: 0,
                recent_activity_summary: "Beta summary"
              },
              %{
                id: "owner-repo-gamma",
                name: "repo-gamma",
                github_full_name: "owner/repo-gamma",
                open_issue_count: 1,
                open_pr_count: 0,
                recent_activity_summary: "Gamma summary"
              }
            ]
          else
            [
              %{
                id: "owner-repo-alpha",
                name: "repo-alpha",
                github_full_name: "owner/repo-alpha",
                open_issue_count: 0,
                open_pr_count: 0,
                recent_activity_summary: "Alpha refreshed summary"
              },
              %{
                id: "owner-repo-beta",
                name: "repo-beta",
                github_full_name: "owner/repo-beta",
                open_issue_count: 4,
                open_pr_count: 2,
                recent_activity_summary: "Beta refreshed summary"
              },
              %{
                id: "owner-repo-gamma",
                name: "repo-gamma",
                github_full_name: "owner/repo-gamma",
                open_issue_count: 3,
                open_pr_count: 0,
                recent_activity_summary: "Gamma refreshed summary"
              }
            ]
          end

        {{:ok, rows, stale_warning}, call_count + 1}
      end)
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    apply_workbench_filters(view, %{"sort_order" => "backlog_desc"})
    assert_project_row_order(view, ["owner-repo-alpha", "owner-repo-beta", "owner-repo-gamma"])

    view
    |> element("#workbench-retry-fetch")
    |> render_click()

    assert_project_row_order(view, ["owner-repo-beta", "owner-repo-gamma", "owner-repo-alpha"])

    assert has_element?(
             view,
             "#workbench-filter-sort-order option[value='backlog_desc'][selected]"
           )

    assert has_element?(view, "#workbench-filter-chip-sort-order", "Backlog size (highest first)")
  end

  test "falls back to default sort order with notice when sort data is malformed", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: "owner-repo-beta",
           name: "repo-beta",
           github_full_name: "owner/repo-beta",
           open_issue_count: 3,
           open_pr_count: 1,
           recent_activity_summary: "Beta summary"
         },
         :invalid_row_payload
       ], nil}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    refute has_element?(view, "#workbench-sort-validation-notice")

    apply_workbench_filters(view, %{"sort_order" => "backlog_desc"})

    assert has_element?(view, "#workbench-sort-validation-notice")

    assert has_element?(
             view,
             "#workbench-sort-validation-type",
             "workbench_sort_order_fallback"
           )

    assert has_element?(view, "#workbench-sort-validation-detail", "Backlog size (highest first)")
    assert has_element?(view, "#workbench-filter-chip-sort-order", "Project name (A-Z)")
    assert has_element?(view, "#workbench-filter-sort-order option[value='project_name_asc'][selected]")
    assert_project_row_order(view, ["owner-repo-beta", "workbench-row-2"])
  end

  test "invalid filter values reset defaults and show typed validation notice", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: "owner-repo-one",
           name: "repo-one",
           github_full_name: "owner/repo-one",
           open_issue_count: 1,
           open_pr_count: 0,
           recent_activity_summary: "Repo one summary"
         },
         %{
           id: "owner-repo-two",
           name: "repo-two",
           github_full_name: "owner/repo-two",
           open_issue_count: 0,
           open_pr_count: 2,
           recent_activity_summary: "Repo two summary"
         }
       ], nil}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    view
    |> element("#workbench-filters-form")
    |> render_change(%{
      "filters" => %{
        "project_id" => "owner-repo-missing",
        "work_state" => "broken-state",
        "freshness_window" => "future-only"
      }
    })

    assert has_element?(view, "#workbench-filter-validation-notice")

    assert has_element?(
             view,
             "#workbench-filter-validation-type",
             "workbench_filter_values_invalid"
           )

    assert has_element?(view, "#workbench-filter-validation-detail", "project_id")
    assert has_element?(view, "#workbench-filter-chip-project", "All projects")
    assert has_element?(view, "#workbench-filter-chip-work-state", "Any issue or PR state")
    assert has_element?(view, "#workbench-filter-chip-freshness-window", "Any freshness")
    assert has_element?(view, "#workbench-filter-chip-sort-order", "Project name (A-Z)")
    assert has_element?(view, "#workbench-filter-results-count", "Showing 2 of 2")
    assert has_element?(view, "#workbench-project-name-owner-repo-one", "owner/repo-one")
    assert has_element?(view, "#workbench-project-name-owner-repo-two", "owner/repo-two")
    assert has_element?(view, "#workbench-filter-project option[value='all'][selected]")
    assert has_element?(view, "#workbench-filter-work-state option[value='all'][selected]")
    assert has_element?(view, "#workbench-filter-freshness-window option[value='any'][selected]")
    assert has_element?(view, "#workbench-filter-sort-order option[value='project_name_asc'][selected]")
  end

  test "preserves filter and sort state across navigation context and restores from workbench URL",
       %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    now = DateTime.utc_now()

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: "owner-repo-alpha",
           name: "repo-alpha",
           github_full_name: "owner/repo-alpha",
           open_issue_count: 2,
           open_pr_count: 0,
           recent_activity_summary: "Alpha summary",
           recent_activity_at: DateTime.add(now, -10 * 24 * 60 * 60, :second) |> DateTime.to_iso8601()
         },
         %{
           id: "owner-repo-beta",
           name: "repo-beta",
           github_full_name: "owner/repo-beta",
           open_issue_count: 0,
           open_pr_count: 3,
           recent_activity_summary: "Beta summary",
           recent_activity_at: DateTime.add(now, -3 * 60 * 60, :second) |> DateTime.to_iso8601()
         }
       ], nil}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    apply_workbench_filters(view, %{
      "project_id" => "owner-repo-beta",
      "work_state" => "prs_open",
      "freshness_window" => "active_24h",
      "sort_order" => "recent_activity_desc"
    })

    workbench_state_path =
      "/workbench?project_id=owner-repo-beta&work_state=prs_open&freshness_window=active_24h&sort_order=recent_activity_desc"

    assert_patch(view, workbench_state_path)
    assert has_element?(view, "#workbench-project-name-owner-repo-beta")
    refute has_element?(view, "#workbench-project-name-owner-repo-alpha")

    encoded_return_to = URI.encode_www_form(workbench_state_path)

    assert has_element?(
             view,
             "#workbench-project-issues-project-link-owner-repo-beta[href='/projects/owner-repo-beta?return_to=#{encoded_return_to}']"
           )

    assert has_element?(
             view,
             "#workbench-project-prs-project-link-owner-repo-beta[href='/projects/owner-repo-beta?return_to=#{encoded_return_to}']"
           )

    {:ok, restored_view, _html} = live(recycle(authed_conn), workbench_state_path, on_error: :warn)

    assert has_element?(restored_view, "#workbench-project-name-owner-repo-beta")
    refute has_element?(restored_view, "#workbench-project-name-owner-repo-alpha")
    assert has_element?(restored_view, "#workbench-filter-chip-project", "owner/repo-beta")
    assert has_element?(restored_view, "#workbench-filter-chip-work-state", "PRs open")
    assert has_element?(restored_view, "#workbench-filter-chip-freshness-window", "Active in last 24 hours")
    assert has_element?(restored_view, "#workbench-filter-chip-sort-order", "Recent activity (most recent first)")
    assert has_element?(restored_view, "#workbench-filter-project option[value='owner-repo-beta'][selected]")
    assert has_element?(restored_view, "#workbench-filter-work-state option[value='prs_open'][selected]")
    assert has_element?(restored_view, "#workbench-filter-freshness-window option[value='active_24h'][selected]")
    assert has_element?(restored_view, "#workbench-filter-sort-order option[value='recent_activity_desc'][selected]")
  end

  test "invalid restored workbench state falls back to defaults with a reset reason notice", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: "owner-repo-one",
           name: "repo-one",
           github_full_name: "owner/repo-one",
           open_issue_count: 1,
           open_pr_count: 0,
           recent_activity_summary: "Repo one summary"
         },
         %{
           id: "owner-repo-two",
           name: "repo-two",
           github_full_name: "owner/repo-two",
           open_issue_count: 0,
           open_pr_count: 2,
           recent_activity_summary: "Repo two summary"
         }
       ], nil}
    end)

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        "/workbench?project_id=owner-repo-missing&sort_order=backlog_desc",
        on_error: :warn
      )

    assert has_element?(view, "#workbench-filter-validation-notice")

    assert has_element?(
             view,
             "#workbench-filter-validation-type",
             "workbench_filter_restore_state_invalid"
           )

    assert has_element?(view, "#workbench-filter-validation-detail", "project_id")
    assert has_element?(view, "#workbench-filter-chip-project", "All projects")
    assert has_element?(view, "#workbench-filter-chip-work-state", "Any issue or PR state")
    assert has_element?(view, "#workbench-filter-chip-freshness-window", "Any freshness")
    assert has_element?(view, "#workbench-filter-chip-sort-order", "Project name (A-Z)")
    assert has_element?(view, "#workbench-filter-project option[value='all'][selected]")
    assert has_element?(view, "#workbench-filter-work-state option[value='all'][selected]")
    assert has_element?(view, "#workbench-filter-freshness-window option[value='any'][selected]")
    assert has_element?(view, "#workbench-filter-sort-order option[value='project_name_asc'][selected]")
    assert has_element?(view, "#workbench-project-name-owner-repo-one", "owner/repo-one")
    assert has_element?(view, "#workbench-project-name-owner-repo-two", "owner/repo-two")
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

  defp apply_workbench_filters(view, overrides) do
    filter_params = Map.merge(default_workbench_filter_params(), overrides)

    view
    |> element("#workbench-filters-form")
    |> render_change(%{"filters" => filter_params})
  end

  defp default_workbench_filter_params do
    %{
      "project_id" => "all",
      "work_state" => "all",
      "freshness_window" => "any",
      "sort_order" => "project_name_asc"
    }
  end

  defp assert_project_row_order(view, row_ids) when is_list(row_ids) do
    row_ids
    |> Enum.with_index(1)
    |> Enum.each(fn {row_id, index} ->
      assert has_element?(
               view,
               "#workbench-project-rows tr:nth-child(#{index}) #workbench-project-name-#{row_id}"
             )
    end)
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
