defmodule JidoCode.Setup.GitHubRepositoryListingTest do
  use ExUnit.Case, async: true

  alias JidoCode.Setup.GitHubRepositoryListing

  @managed_env_keys [:setup_github_repository_fetcher]

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

    :ok
  end

  test "run/2 lists only repositories from credential paths with confirmed access and exposes stable identifiers" do
    onboarding_state = %{
      "4" => %{
        "github_credentials" => %{
          "paths" => [
            %{
              "path" => "github_app",
              "status" => "ready",
              "repository_access" => "confirmed",
              "repositories" => [
                %{"id" => "repo_200", "full_name" => "owner/repo-two"},
                "owner/repo-one"
              ]
            },
            %{
              "path" => "pat",
              "status" => "invalid",
              "repository_access" => "unconfirmed",
              "repositories" => ["owner/private-repo"]
            }
          ]
        }
      }
    }

    report = GitHubRepositoryListing.run(nil, onboarding_state)

    refute GitHubRepositoryListing.blocked?(report)
    assert report.status == :ready

    assert GitHubRepositoryListing.repository_full_names(report) == [
             "owner/repo-one",
             "owner/repo-two"
           ]

    repositories_by_name =
      report.repositories
      |> Enum.map(fn repository -> {repository.full_name, repository} end)
      |> Map.new()

    assert repositories_by_name["owner/repo-one"].id == "repo:owner/repo-one"
    assert repositories_by_name["owner/repo-two"].id == "repo_200"
  end

  test "run/2 preserves previously listed repositories when listing fetch fails" do
    onboarding_state = %{
      "4" => %{
        "github_credentials" => %{
          "paths" => [
            %{
              "path" => "github_app",
              "status" => "ready",
              "repositories" => ["owner/repo-one"]
            }
          ]
        }
      }
    }

    previous_report = GitHubRepositoryListing.run(nil, onboarding_state)
    refute GitHubRepositoryListing.blocked?(previous_report)

    Application.put_env(:jido_code, :setup_github_repository_fetcher, fn _context ->
      {:error, {"github_repository_fetch_timeout", "GitHub API request timed out."}}
    end)

    report = GitHubRepositoryListing.run(previous_report, onboarding_state)

    assert GitHubRepositoryListing.blocked?(report)
    assert report.error_type == "github_repository_fetch_timeout"
    assert report.repositories == previous_report.repositories
    assert report.detail =~ "preserved for retry"
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
