defmodule JidoCode.Setup.GitHubCredentialChecksTest do
  use ExUnit.Case, async: true

  alias JidoCode.Setup.GitHubCredentialChecks

  @checked_at ~U[2026-02-13 12:34:56Z]

  setup do
    original_checker =
      Application.get_env(:jido_code, :setup_github_credential_checker, :__missing__)

    on_exit(fn ->
      restore_env(:setup_github_credential_checker, original_checker)
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

    github_app_path = Enum.find(report.paths, fn path_result -> path_result.path == :github_app end)
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

    [restored_path] = restored.paths
    assert restored_path.status == :ready
    assert restored_path.repository_access == :confirmed
    assert %DateTime{} = restored_path.validated_at
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
