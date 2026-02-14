defmodule JidoCode.Setup.GitHubCredentialChecksTest do
  use ExUnit.Case, async: true

  alias JidoCode.Setup.GitHubCredentialChecks

  @checked_at ~U[2026-02-13 12:34:56Z]
  @managed_env_keys [
    :setup_github_credential_checker,
    :github_app_id,
    :github_app_private_key,
    :github_app_accessible_repos,
    :github_app_expected_repos,
    :github_expected_repos,
    :github_pat,
    :github_pat_accessible_repos
  ]

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

  test "run/2 allows progression when PAT fallback confirms repository access" do
    Application.put_env(:jido_code, :setup_github_credential_checker, fn _context ->
      %{
        checked_at: @checked_at,
        status: :ready,
        owner_context: "owner@example.com",
        paths: [
          %{
            path: :github_app,
            name: "GitHub App",
            status: :invalid,
            detail: "GitHub App credentials failed validation.",
            remediation: "Set valid GitHub App credentials and retry validation.",
            error_type: "github_app_credentials_invalid",
            repository_access: :unconfirmed,
            checked_at: @checked_at
          },
          %{
            path: :pat,
            name: "Personal Access Token (PAT)",
            status: :ready,
            detail: "GitHub PAT fallback confirms repository access.",
            remediation: "Credential path is ready.",
            repository_access: :confirmed,
            repositories: ["owner/repo-one"],
            validated_at: @checked_at,
            checked_at: @checked_at
          }
        ]
      }
    end)

    report = GitHubCredentialChecks.run(nil, "owner@example.com")

    refute GitHubCredentialChecks.blocked?(report)

    github_app_path =
      Enum.find(report.paths, fn path_result -> path_result.path == :github_app end)

    pat_path = Enum.find(report.paths, fn path_result -> path_result.path == :pat end)

    assert github_app_path.status == :invalid
    assert github_app_path.error_type == "github_app_credentials_invalid"

    assert pat_path.status == :ready
    assert pat_path.repository_access == :confirmed
    assert pat_path.transition == "Not configured -> Ready"
    assert %DateTime{} = pat_path.validated_at
  end

  test "run/2 blocks progression when both GitHub credential paths fail" do
    Application.put_env(:jido_code, :setup_github_credential_checker, fn _context ->
      %{
        checked_at: @checked_at,
        status: :blocked,
        owner_context: "owner@example.com",
        paths: [
          %{
            path: :github_app,
            name: "GitHub App",
            status: :invalid,
            detail: "Configured GitHub App credentials failed validation.",
            remediation: "Set valid GitHub App credentials and retry validation.",
            error_type: "github_app_credentials_invalid",
            repository_access: :unconfirmed,
            checked_at: @checked_at
          },
          %{
            path: :pat,
            name: "Personal Access Token (PAT)",
            status: :invalid,
            detail: "Configured GitHub PAT failed validation.",
            remediation: "Set a valid `GITHUB_PAT` and retry validation.",
            error_type: "github_pat_credentials_invalid",
            repository_access: :unconfirmed,
            checked_at: @checked_at
          }
        ]
      }
    end)

    report = GitHubCredentialChecks.run(nil, "owner@example.com")

    assert GitHubCredentialChecks.blocked?(report)

    blocked_paths =
      report
      |> GitHubCredentialChecks.blocked_paths()
      |> Enum.map(fn path_result -> path_result.error_type end)

    assert "github_app_credentials_invalid" in blocked_paths
    assert "github_pat_credentials_invalid" in blocked_paths
  end

  test "run/2 blocks when GitHub App installation access is missing expected repositories" do
    Application.delete_env(:jido_code, :setup_github_credential_checker)
    Application.put_env(:jido_code, :github_app_id, "1234")
    Application.put_env(:jido_code, :github_app_private_key, "test-private-key")
    Application.put_env(:jido_code, :github_app_accessible_repos, ["owner/repo-one"])

    Application.put_env(:jido_code, :github_app_expected_repos, [
      "owner/repo-one",
      "owner/repo-two"
    ])

    report = GitHubCredentialChecks.run(nil, "owner@example.com")

    assert GitHubCredentialChecks.blocked?(report)

    github_app_path =
      Enum.find(report.paths, fn path_result -> path_result.path == :github_app end)

    assert github_app_path.status == :invalid
    assert github_app_path.expected_repositories == ["owner/repo-one", "owner/repo-two"]
    assert github_app_path.missing_repositories == ["owner/repo-two"]
    assert github_app_path.error_type == "github_app_installation_access_missing_repositories"

    assert report.integration_health.readiness_status == :blocked
    assert report.integration_health.github_app_status == :invalid
    assert report.integration_health.missing_repositories == ["owner/repo-two"]
  end

  test "serialize_for_state/1 preserves owner context and ready-path validation metadata" do
    Application.put_env(:jido_code, :setup_github_credential_checker, fn _context ->
      %{
        checked_at: @checked_at,
        status: :ready,
        owner_context: "owner@example.com",
        paths: [
          %{
            path: :github_app,
            name: "GitHub App",
            status: :ready,
            detail: "GitHub App credentials are valid.",
            remediation: "Credential path is ready.",
            repository_access: :confirmed,
            repositories: ["owner/repo-one"],
            validated_at: @checked_at,
            checked_at: @checked_at
          }
        ]
      }
    end)

    report = GitHubCredentialChecks.run(nil, "owner@example.com")
    serialized = GitHubCredentialChecks.serialize_for_state(report)
    restored = GitHubCredentialChecks.from_state(serialized)

    assert serialized["status"] == "ready"
    assert serialized["owner_context"] == "owner@example.com"
    assert serialized["integration_health"]["readiness_status"] == "ready"
    assert serialized["integration_health"]["github_app_status"] == "ready"
    assert serialized["integration_health"]["github_app_ready"] == true
    assert serialized["integration_health"]["last_checked_at"] == DateTime.to_iso8601(@checked_at)

    [restored_path] = restored.paths
    assert restored_path.status == :ready
    assert restored_path.repository_access == :confirmed
    assert %DateTime{} = restored_path.validated_at

    restored_integration_health = Map.fetch!(restored, :integration_health)
    assert Map.fetch!(restored_integration_health, :readiness_status) == :ready
    assert Map.fetch!(restored_integration_health, :github_app_status) == :ready
    assert Map.fetch!(restored_integration_health, :github_app_ready)
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
