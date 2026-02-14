defmodule JidoCode.Setup.GitHubInstallationSyncTest do
  use ExUnit.Case, async: true

  alias JidoCode.Setup.GitHubInstallationSync

  @managed_env_keys [:system_config, :system_config_loader, :system_config_saver]

  setup do
    original_env =
      Enum.map(@managed_env_keys, fn key ->
        {key, Application.get_env(:jido_code, key, :__missing__)}
      end)

    on_exit(fn ->
      Enum.each(original_env, fn {key, value} ->
        restore_env(key, value)
      end)
    end)

    Application.delete_env(:jido_code, :system_config_loader)
    Application.delete_env(:jido_code, :system_config_saver)

    :ok
  end

  test "sync_verified_delivery/1 updates accessible repositories for installation_repositories events" do
    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 7,
      onboarding_state: %{
        "4" => %{
          "github_credentials" => %{
            "paths" => [
              %{
                "path" => "github_app",
                "status" => "ready",
                "repository_access" => "confirmed",
                "repositories" => ["owner/repo-one"]
              }
            ]
          }
        }
      }
    })

    assert {:ok, summary} =
             GitHubInstallationSync.sync_verified_delivery(%{
               event: "installation_repositories",
               payload: %{
                 "action" => "added",
                 "installation" => %{"id" => 321},
                 "repositories_added" => [%{"id" => "repo_200", "full_name" => "owner/repo-two"}],
                 "repositories_removed" => []
               }
             })

    assert summary.status == :ready
    assert summary.event == "installation_repositories"
    assert summary.action == "added"
    assert summary.installation_id == 321
    assert GitHubInstallationSync.repository_names(summary) == ["owner/repo-one", "owner/repo-two"]

    persisted_onboarding_state =
      Application.get_env(:jido_code, :system_config)
      |> Map.fetch!(:onboarding_state)

    installation_sync =
      persisted_onboarding_state
      |> Map.fetch!("7")
      |> Map.fetch!("installation_sync")

    assert installation_sync["status"] == "ready"
    assert installation_sync["installation_id"] == 321

    assert Enum.map(installation_sync["accessible_repositories"], & &1["full_name"]) == [
             "owner/repo-one",
             "owner/repo-two"
           ]
  end

  test "sync_verified_delivery/1 records stale-state warning when installation payload is missing installation id" do
    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 7,
      onboarding_state: %{
        "4" => %{
          "github_credentials" => %{
            "paths" => [
              %{
                "path" => "github_app",
                "status" => "ready",
                "repository_access" => "confirmed",
                "repositories" => ["owner/repo-one"]
              }
            ]
          }
        }
      }
    })

    assert {:error, stale_summary} =
             GitHubInstallationSync.sync_verified_delivery(%{
               event: "installation",
               payload: %{
                 "action" => "created",
                 "repositories" => [%{"full_name" => "owner/repo-one"}]
               }
             })

    assert stale_summary.status == :stale
    assert stale_summary.error_type == "github_installation_sync_stale"
    assert stale_summary.detail =~ "Repository availability may be stale"
    assert stale_summary.remediation =~ "Retry repository refresh in step 7"

    persisted_onboarding_state =
      Application.get_env(:jido_code, :system_config)
      |> Map.fetch!(:onboarding_state)

    repository_listing =
      persisted_onboarding_state
      |> Map.fetch!("7")
      |> Map.fetch!("repository_listing")

    assert repository_listing["status"] == "blocked"
    assert repository_listing["error_type"] == "github_installation_sync_stale"
    assert repository_listing["detail"] =~ "Repository availability may be stale"
    assert repository_listing["remediation"] =~ "Retry repository refresh in step 7"
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
