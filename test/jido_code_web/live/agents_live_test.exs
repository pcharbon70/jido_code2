defmodule JidoCodeWeb.AgentsLiveTest do
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User
  alias JidoCode.Projects.Project

  setup do
    original_project_loader =
      Application.get_env(:jido_code, :support_agent_config_project_loader, :__missing__)

    original_project_updater =
      Application.get_env(:jido_code, :support_agent_config_project_updater, :__missing__)

    on_exit(fn ->
      restore_env(:support_agent_config_project_loader, original_project_loader)
      restore_env(:support_agent_config_project_updater, original_project_updater)
    end)

    :ok
  end

  test "agents page exposes enable and disable controls and persists issue bot enabled state per project",
       %{
         conn: _conn
       } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project_enabled} =
      Project.create(%{
        name: "repo-enabled",
        github_full_name: "owner/repo-enabled",
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{"enabled" => true}
          }
        }
      })

    {:ok, project_disabled} =
      Project.create(%{
        name: "repo-disabled",
        github_full_name: "owner/repo-disabled",
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{"enabled" => false}
          }
        }
      })

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/agents", on_error: :warn)

    assert has_element?(view, "#agents-project-table")

    assert has_element?(
             view,
             "#agents-project-github-full-name-#{project_enabled.id}",
             "owner/repo-enabled"
           )

    assert has_element?(
             view,
             "#agents-project-github-full-name-#{project_disabled.id}",
             "owner/repo-disabled"
           )

    assert has_element?(view, "#agents-issue-bot-enable-#{project_enabled.id}")
    assert has_element?(view, "#agents-issue-bot-disable-#{project_enabled.id}")
    assert has_element?(view, "#agents-issue-bot-enable-#{project_disabled.id}")
    assert has_element?(view, "#agents-issue-bot-disable-#{project_disabled.id}")

    assert has_element?(view, "#agents-issue-bot-status-#{project_enabled.id}", "Enabled")
    assert has_element?(view, "#agents-issue-bot-status-#{project_disabled.id}", "Disabled")

    view
    |> element("#agents-issue-bot-disable-#{project_enabled.id}")
    |> render_click()

    assert has_element?(view, "#agents-issue-bot-status-#{project_enabled.id}", "Disabled")

    refreshed_project_enabled = read_project!(project_enabled.id)
    assert issue_bot_enabled(refreshed_project_enabled.settings) == false

    view
    |> element("#agents-issue-bot-enable-#{project_disabled.id}")
    |> render_click()

    assert has_element?(view, "#agents-issue-bot-status-#{project_disabled.id}", "Enabled")

    refreshed_project_disabled = read_project!(project_disabled.id)
    assert issue_bot_enabled(refreshed_project_disabled.settings) == true
  end

  test "persistence failure leaves enabled state unchanged and renders typed error feedback", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-failure",
        github_full_name: "owner/repo-failure",
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{"enabled" => true}
          }
        }
      })

    Application.put_env(:jido_code, :support_agent_config_project_updater, fn _project, _update_attributes ->
      {:error, :forced_support_agent_config_failure}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/agents", on_error: :warn)

    assert has_element?(view, "#agents-issue-bot-status-#{project.id}", "Enabled")

    view
    |> element("#agents-issue-bot-disable-#{project.id}")
    |> render_click()

    assert has_element?(
             view,
             "#agents-issue-bot-error-type",
             "support_agent_config_persistence_failed"
           )

    assert has_element?(view, "#agents-issue-bot-status-#{project.id}", "Enabled")

    refreshed_project = read_project!(project.id)
    assert issue_bot_enabled(refreshed_project.settings) == true
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

  defp read_project!(project_id) do
    {:ok, [project]} = Project.read(query: [filter: [id: project_id], limit: 1])
    project
  end

  defp issue_bot_enabled(settings) when is_map(settings) do
    settings
    |> map_get(:support_agent_config, "support_agent_config", %{})
    |> normalize_map()
    |> map_get(:github_issue_bot, "github_issue_bot", %{})
    |> normalize_map()
    |> map_get(:enabled, "enabled", true)
    |> case do
      true -> true
      "true" -> true
      false -> false
      "false" -> false
      _other -> true
    end
  end

  defp issue_bot_enabled(_settings), do: true

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

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp map_get(map, atom_key, string_key, default)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default
end
