defmodule JidoCodeWeb.SetupLiveTest do
  use JidoCodeWeb.ConnCase, async: false

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts
  alias JidoCode.Accounts.User
  alias JidoCode.Repo

  import Phoenix.LiveViewTest

  @checked_at ~U[2026-02-13 12:34:56Z]

  setup do
    original_loader = Application.get_env(:jido_code, :system_config_loader, :__missing__)
    original_saver = Application.get_env(:jido_code, :system_config_saver, :__missing__)
    original_config = Application.get_env(:jido_code, :system_config, :__missing__)
    original_checker = Application.get_env(:jido_code, :setup_prerequisite_checker, :__missing__)

    original_provider_checker =
      Application.get_env(:jido_code, :setup_provider_credential_checker, :__missing__)

    original_github_checker =
      Application.get_env(:jido_code, :setup_github_credential_checker, :__missing__)

    original_runtime_mode = Application.get_env(:jido_code, :runtime_mode, :__missing__)

    original_timeout =
      Application.get_env(:jido_code, :setup_prerequisite_timeout_ms, :__missing__)

    on_exit(fn ->
      restore_env(:system_config_loader, original_loader)
      restore_env(:system_config_saver, original_saver)
      restore_env(:system_config, original_config)
      restore_env(:setup_prerequisite_checker, original_checker)
      restore_env(:setup_provider_credential_checker, original_provider_checker)
      restore_env(:setup_github_credential_checker, original_github_checker)
      restore_env(:setup_prerequisite_timeout_ms, original_timeout)
      restore_env(:runtime_mode, original_runtime_mode)
    end)

    Application.delete_env(:jido_code, :system_config_loader)
    Application.delete_env(:jido_code, :system_config_saver)
    Application.delete_env(:jido_code, :setup_prerequisite_timeout_ms)
    Application.delete_env(:jido_code, :setup_provider_credential_checker)
    Application.delete_env(:jido_code, :setup_github_credential_checker)
    Application.put_env(:jido_code, :runtime_mode, :test)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 1,
      onboarding_state: %{}
    })

    Application.put_env(:jido_code, :setup_prerequisite_checker, fn _timeout_ms ->
      passing_prerequisite_report()
    end)

    Application.put_env(:jido_code, :setup_provider_credential_checker, fn _context ->
      passing_provider_credential_report()
    end)

    Application.put_env(:jido_code, :setup_github_credential_checker, fn _context ->
      passing_github_credential_report()
    end)

    reset_owner_state!()

    :ok
  end

  test "step 1 shows timestamped prerequisite checks and persists progression on success", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-prerequisite-status")
    assert has_element?(view, "#setup-prerequisite-checked-at", "2026-02-13T12:34:56Z")
    assert has_element?(view, "#setup-prerequisite-database_connectivity-status", "Pass")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Prerequisite checks passed"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 2")

    assert %{
             onboarding_step: 2,
             onboarding_state: %{
               "1" => %{
                 "validated_note" => "Prerequisite checks passed",
                 "prerequisite_checks" => %{"status" => "pass"}
               }
             }
           } = Application.get_env(:jido_code, :system_config)

    {:ok, resumed_view, _html} = live(build_conn(), ~p"/setup", on_error: :warn)

    assert has_element?(resumed_view, "#resolved-onboarding-step", "Step 2")
    assert has_element?(resumed_view, "#validated-state-step-1", "Prerequisite checks passed")
    assert has_element?(resumed_view, "#setup-owner-bootstrap-form")
  end

  test "step 1 validation failure shows remediation and blocks persistence", %{conn: conn} do
    test_pid = self()

    Application.put_env(:jido_code, :setup_prerequisite_checker, fn _timeout_ms ->
      failing_prerequisite_report()
    end)

    Application.put_env(:jido_code, :system_config_saver, fn _config ->
      send(test_pid, :unexpected_save)
      {:ok, %{onboarding_completed: false, onboarding_step: 2, onboarding_state: %{}}}
    end)

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(
             view,
             "#setup-prerequisite-remediation-runtime_token_signing_secret",
             "TOKEN_SIGNING_SECRET"
           )

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Attempting to bypass failing prerequisites"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 1")
    assert has_element?(view, "#setup-save-error", "System prerequisite checks failed")
    assert has_element?(view, "#setup-save-error", "TOKEN_SIGNING_SECRET")
    refute_received :unexpected_save

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 1
    assert Map.fetch!(persisted_config, :onboarding_state) == %{}
  end

  test "step 2 creates owner when none exists and grants immediate protected-route session access",
       %{conn: conn} do
    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 2,
      onboarding_state: %{"1" => %{"validated_note" => "Prerequisite checks passed"}}
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-owner-bootstrap-mode", "No owner account exists yet")

    view
    |> form("#setup-owner-bootstrap-form", %{
      "owner" => %{
        "email" => "owner@example.com",
        "password" => "owner-password-123",
        "password_confirmation" => "owner-password-123"
      }
    })
    |> render_submit()

    auth_redirect_path =
      view
      |> assert_redirect()
      |> redirect_path()

    assert auth_redirect_path =~ "/auth/"
    assert auth_redirect_path =~ "sign_in_with_token"

    authed_response = build_conn() |> get(auth_redirect_path)
    assert redirected_to(authed_response, 302) == "/"

    {:ok, dashboard_view, _html} = live(recycle(authed_response), ~p"/dashboard", on_error: :warn)
    assert has_element?(dashboard_view, "p", "owner@example.com")

    assert_owner_count(1)

    assert %{
             onboarding_step: 3,
             onboarding_state: %{
               "2" => %{
                 "owner_email" => "owner@example.com",
                 "owner_mode" => "created",
                 "validated_note" => "Owner account bootstrapped."
               }
             }
           } = Application.get_env(:jido_code, :system_config)
  end

  test "step 2 confirms existing owner and grants immediate protected-route session access", %{
    conn: conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 2,
      onboarding_state: %{"1" => %{"validated_note" => "Prerequisite checks passed"}}
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-owner-bootstrap-mode", "owner account already exists")
    assert has_element?(view, "#setup-owner-bootstrap-owner-email", "owner@example.com")

    view
    |> form("#setup-owner-bootstrap-form", %{
      "owner" => %{
        "email" => "owner@example.com",
        "password" => "owner-password-123"
      }
    })
    |> render_submit()

    auth_redirect_path =
      view
      |> assert_redirect()
      |> redirect_path()

    authed_response = build_conn() |> get(auth_redirect_path)
    assert redirected_to(authed_response, 302) == "/"

    {:ok, dashboard_view, _html} = live(recycle(authed_response), ~p"/dashboard", on_error: :warn)
    assert has_element?(dashboard_view, "p", "owner@example.com")

    assert_owner_count(1)

    assert %{
             onboarding_step: 3,
             onboarding_state: %{
               "2" => %{
                 "owner_email" => "owner@example.com",
                 "owner_mode" => "confirmed",
                 "validated_note" => "Owner account confirmed."
               }
             }
           } = Application.get_env(:jido_code, :system_config)
  end

  test "step 2 blocks additional owner creation attempts with a single-user policy error", %{
    conn: conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 2,
      onboarding_state: %{"1" => %{"validated_note" => "Prerequisite checks passed"}}
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    view
    |> form("#setup-owner-bootstrap-form", %{
      "owner" => %{
        "email" => "second-owner@example.com",
        "password" => "another-password-123"
      }
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 2")
    assert has_element?(view, "#setup-save-error", "Single-user policy error")

    assert_owner_count(1)

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 2
  end

  test "production step 2 marks registration actions disabled and keeps owner login available while blocking registration",
       %{conn: conn} do
    Application.put_env(:jido_code, :runtime_mode, :prod)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 2,
      onboarding_state: %{"1" => %{"validated_note" => "Prerequisite checks passed"}}
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    view
    |> form("#setup-owner-bootstrap-form", %{
      "owner" => %{
        "email" => "owner@example.com",
        "password" => "owner-password-123",
        "password_confirmation" => "owner-password-123"
      }
    })
    |> render_submit()

    auth_redirect_path =
      view
      |> assert_redirect()
      |> redirect_path()

    authed_response = build_conn() |> get(auth_redirect_path)
    assert redirected_to(authed_response, 302) == "/"

    strategy = Info.strategy!(User, :password)

    assert {:ok, _owner} =
             Strategy.action(
               strategy,
               :sign_in,
               %{"email" => "owner@example.com", "password" => "owner-password-123"},
               context: %{token_type: :sign_in}
             )

    assert {:error, %Ash.Error.Forbidden{} = error} =
             Strategy.action(
               strategy,
               :register,
               %{
                 "email" => "another-user@example.com",
                 "password" => "owner-password-123",
                 "password_confirmation" => "owner-password-123"
               },
               context: %{token_type: :sign_in}
             )

    assert Enum.any?(error.errors, &match?(%Ash.Error.Forbidden.Policy{}, &1))
    assert_owner_count(1)

    assert %{
             onboarding_step: 3,
             onboarding_state: %{
               "2" => %{
                 "owner_email" => "owner@example.com",
                 "owner_mode" => "created",
                 "registration_actions_disabled" => true,
                 "validated_note" => "Owner account bootstrapped."
               }
             }
           } = Application.get_env(:jido_code, :system_config)
  end

  test "production registration request fails with a typed authorization error once owner exists" do
    Application.put_env(:jido_code, :runtime_mode, :prod)
    register_owner("owner@example.com", "owner-password-123")

    strategy = Info.strategy!(User, :password)

    assert {:error, %Ash.Error.Forbidden{} = error} =
             Strategy.action(
               strategy,
               :register,
               %{
                 "email" => "blocked-user@example.com",
                 "password" => "owner-password-123",
                 "password_confirmation" => "owner-password-123"
               },
               context: %{token_type: :sign_in}
             )

    assert Enum.any?(error.errors, &match?(%Ash.Error.Forbidden.Policy{}, &1))
  end

  test "step 1 timeout keeps onboarding blocked and does not persist downstream data", %{
    conn: conn
  } do
    test_pid = self()

    Application.put_env(:jido_code, :setup_prerequisite_checker, fn _timeout_ms ->
      timeout_prerequisite_report()
    end)

    Application.put_env(:jido_code, :system_config_saver, fn _config ->
      send(test_pid, :unexpected_save)
      {:ok, %{onboarding_completed: false, onboarding_step: 2, onboarding_state: %{}}}
    end)

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)
    assert has_element?(view, "#setup-prerequisite-runtime_phx_host-status", "Timeout")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Attempting to continue after timeout"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 1")
    assert has_element?(view, "#setup-save-error", "timed out")
    assert has_element?(view, "#setup-save-error", "no setup progress was saved")
    refute_received :unexpected_save

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 1
    assert Map.fetch!(persisted_config, :onboarding_state) == %{}
  end

  test "step 3 requires one active provider and persists verified provider status before GitHub setup",
       %{conn: conn} do
    Application.put_env(:jido_code, :setup_provider_credential_checker, fn _context ->
      mixed_provider_credential_report()
    end)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "1" => %{"validated_note" => "Prerequisite checks passed"},
        "2" => %{"validated_note" => "Owner account confirmed"}
      }
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-provider-anthropic-status", "Active")
    assert has_element?(view, "#setup-provider-transition-anthropic", "Not set -> Active")
    assert has_element?(view, "#setup-provider-openai-status", "Invalid")
    assert has_element?(view, "#setup-provider-remediation-openai", "OPENAI_API_KEY")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Provider setup confirmed"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 4")

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 4

    provider_state =
      persisted_config
      |> Map.fetch!(:onboarding_state)
      |> Map.fetch!("3")
      |> Map.fetch!("provider_credentials")

    assert provider_state["status"] == "active"

    credentials_by_provider =
      provider_state["credentials"]
      |> Enum.map(fn credential -> {credential["provider"], credential} end)
      |> Map.new()

    assert credentials_by_provider["anthropic"]["status"] == "active"
    assert is_binary(credentials_by_provider["anthropic"]["verified_at"])
    assert credentials_by_provider["openai"]["status"] == "invalid"
    assert is_nil(credentials_by_provider["openai"]["verified_at"])
  end

  test "step 3 blocks progression when all provider checks fail and does not save false success",
       %{conn: conn} do
    test_pid = self()

    Application.put_env(:jido_code, :setup_provider_credential_checker, fn _context ->
      failing_provider_credential_report()
    end)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "1" => %{"validated_note" => "Prerequisite checks passed"},
        "2" => %{"validated_note" => "Owner account confirmed"}
      }
    })

    Application.put_env(:jido_code, :system_config_saver, fn _config ->
      send(test_pid, :unexpected_save)
      {:ok, %{onboarding_completed: false, onboarding_step: 4, onboarding_state: %{}}}
    end)

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-provider-anthropic-status", "Not set")
    assert has_element?(view, "#setup-provider-openai-status", "Invalid")
    assert has_element?(view, "#setup-provider-transition-openai", "Not set -> Invalid")
    assert has_element?(view, "#setup-provider-remediation-openai", "OPENAI_API_KEY")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Attempting provider bypass"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 3")
    assert has_element?(view, "#setup-save-error", "must verify as Active")
    assert has_element?(view, "#setup-save-error", "No setup progress was saved")
    refute_received :unexpected_save

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 3
    refute Map.has_key?(Map.fetch!(persisted_config, :onboarding_state), "3")
  end

  test "step 4 validates GitHub App or PAT fallback and persists owner-context repository access",
       %{conn: conn} do
    Application.put_env(:jido_code, :setup_github_credential_checker, fn _context ->
      mixed_github_credential_report()
    end)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 4,
      onboarding_state: %{
        "1" => %{"validated_note" => "Prerequisite checks passed"},
        "2" => %{
          "validated_note" => "Owner account confirmed",
          "owner_email" => "owner@example.com"
        },
        "3" => %{"validated_note" => "Provider setup confirmed"}
      }
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-github-checked-at", "2026-02-13T12:34:56Z")
    assert has_element?(view, "#setup-github-owner-context", "owner@example.com")
    assert has_element?(view, "#setup-github-github_app-status", "Invalid")
    assert has_element?(view, "#setup-github-error-type-github_app", "github_app_repository_access_unverified")
    assert has_element?(view, "#setup-github-pat-status", "Ready")
    assert has_element?(view, "#setup-github-repository-access-pat", "Confirmed")
    assert has_element?(view, "#setup-github-repositories-pat", "owner/repo-one")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "GitHub credentials validated"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 5")

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 5

    github_state =
      persisted_config
      |> Map.fetch!(:onboarding_state)
      |> Map.fetch!("4")
      |> Map.fetch!("github_credentials")

    assert github_state["status"] == "ready"
    assert github_state["owner_context"] == "owner@example.com"

    paths_by_type =
      github_state["paths"]
      |> Enum.map(fn path_result -> {path_result["path"], path_result} end)
      |> Map.new()

    assert paths_by_type["pat"]["status"] == "ready"
    assert paths_by_type["pat"]["repository_access"] == "confirmed"
    assert is_binary(paths_by_type["pat"]["validated_at"])
    assert paths_by_type["github_app"]["status"] == "invalid"
    assert paths_by_type["github_app"]["error_type"] == "github_app_repository_access_unverified"
  end

  test "step 4 blocks progression with typed integration errors when GitHub App and PAT fail",
       %{conn: conn} do
    test_pid = self()

    Application.put_env(:jido_code, :setup_github_credential_checker, fn _context ->
      failing_github_credential_report()
    end)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 4,
      onboarding_state: %{
        "1" => %{"validated_note" => "Prerequisite checks passed"},
        "2" => %{
          "validated_note" => "Owner account confirmed",
          "owner_email" => "owner@example.com"
        },
        "3" => %{"validated_note" => "Provider setup confirmed"}
      }
    })

    Application.put_env(:jido_code, :system_config_saver, fn _config ->
      send(test_pid, :unexpected_save)
      {:ok, %{onboarding_completed: false, onboarding_step: 5, onboarding_state: %{}}}
    end)

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-github-github_app-status", "Invalid")
    assert has_element?(view, "#setup-github-pat-status", "Invalid")
    assert has_element?(view, "#setup-github-error-type-github_app", "github_app_credentials_invalid")
    assert has_element?(view, "#setup-github-error-type-pat", "github_pat_credentials_invalid")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Attempting GitHub setup bypass"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 4")
    assert has_element?(view, "#setup-save-error", "typed integration errors")
    assert has_element?(view, "#setup-save-error", "github_app_credentials_invalid")
    assert has_element?(view, "#setup-save-error", "github_pat_credentials_invalid")
    refute_received :unexpected_save

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 4
    refute Map.has_key?(Map.fetch!(persisted_config, :onboarding_state), "4")
  end

  test "save failure keeps the same step and shows a retry-safe error", %{conn: conn} do
    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "1" => %{"validated_note" => "Prerequisite checks passed"},
        "2" => %{"validated_note" => "Owner account confirmed"}
      }
    })

    Application.put_env(:jido_code, :system_config_saver, fn _config ->
      {:error, :database_unreachable}
    end)

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)
    assert has_element?(view, "#resolved-onboarding-step", "Step 3")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Provider setup confirmed"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 3")
    assert has_element?(view, "#setup-save-error", "safely retry this step")
    assert has_element?(view, "#validated-state-step-1", "Prerequisite checks passed")
    assert has_element?(view, "#validated-state-step-2", "Owner account confirmed")

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 3
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)

  defp register_owner(email, password) do
    strategy = Info.strategy!(User, :password)

    {:ok, owner} =
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

    owner
  end

  defp assert_owner_count(expected_count) do
    {:ok, owners} = Ash.read(User, domain: Accounts, authorize?: false)
    assert length(owners) == expected_count
  end

  defp passing_prerequisite_report do
    %{
      checked_at: @checked_at,
      status: :pass,
      checks: [
        %{
          id: "database_connectivity",
          name: "Database connectivity",
          status: :pass,
          detail: "Successfully connected to Postgres.",
          remediation: "Confirm Postgres is reachable and verify `DATABASE_URL` or Repo runtime config.",
          checked_at: @checked_at
        },
        %{
          id: "runtime_token_signing_secret",
          name: "Runtime configuration: TOKEN_SIGNING_SECRET",
          status: :pass,
          detail: "Runtime configuration: TOKEN_SIGNING_SECRET is configured.",
          remediation: "Set `TOKEN_SIGNING_SECRET` in runtime config (or env) and restart JidoCode.",
          checked_at: @checked_at
        },
        %{
          id: "runtime_secret_key_base",
          name: "Runtime configuration: SECRET_KEY_BASE",
          status: :pass,
          detail: "Runtime configuration: SECRET_KEY_BASE is configured.",
          remediation: "Set endpoint `secret_key_base` (or env `SECRET_KEY_BASE`) and restart JidoCode.",
          checked_at: @checked_at
        },
        %{
          id: "runtime_phx_host",
          name: "Runtime configuration: PHX_HOST",
          status: :pass,
          detail: "Runtime configuration: PHX_HOST is configured.",
          remediation: "Set endpoint URL host (or env `PHX_HOST`) and restart JidoCode.",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp failing_prerequisite_report do
    %{
      checked_at: @checked_at,
      status: :fail,
      checks: [
        %{
          id: "database_connectivity",
          name: "Database connectivity",
          status: :pass,
          detail: "Successfully connected to Postgres.",
          remediation: "Confirm Postgres is reachable and verify `DATABASE_URL` or Repo runtime config.",
          checked_at: @checked_at
        },
        %{
          id: "runtime_token_signing_secret",
          name: "Runtime configuration: TOKEN_SIGNING_SECRET",
          status: :fail,
          detail: "Required runtime value `TOKEN_SIGNING_SECRET` is missing.",
          remediation: "Set `TOKEN_SIGNING_SECRET` in runtime config (or env) and restart JidoCode.",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp timeout_prerequisite_report do
    %{
      checked_at: @checked_at,
      status: :timeout,
      checks: [
        %{
          id: "database_connectivity",
          name: "Database connectivity",
          status: :pass,
          detail: "Successfully connected to Postgres.",
          remediation: "Confirm Postgres is reachable and verify `DATABASE_URL` or Repo runtime config.",
          checked_at: @checked_at
        },
        %{
          id: "runtime_phx_host",
          name: "Runtime configuration: PHX_HOST",
          status: :timeout,
          detail: "Check timed out after 3000ms.",
          remediation: "Set endpoint URL host (or env `PHX_HOST`) and restart JidoCode.",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp passing_provider_credential_report do
    %{
      checked_at: @checked_at,
      status: :active,
      credentials: [
        %{
          provider: :anthropic,
          name: "Anthropic",
          status: :active,
          detail: "ANTHROPIC_API_KEY is configured and passed verification checks.",
          remediation: "Credential is active.",
          verified_at: @checked_at,
          checked_at: @checked_at
        },
        %{
          provider: :openai,
          name: "OpenAI",
          status: :not_set,
          detail: "No OPENAI_API_KEY credential is configured.",
          remediation: "Set `OPENAI_API_KEY` and retry verification.",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp mixed_provider_credential_report do
    %{
      checked_at: @checked_at,
      status: :active,
      credentials: [
        %{
          provider: :anthropic,
          name: "Anthropic",
          status: :active,
          detail: "ANTHROPIC_API_KEY is configured and passed verification checks.",
          remediation: "Credential is active.",
          verified_at: @checked_at,
          checked_at: @checked_at
        },
        %{
          provider: :openai,
          name: "OpenAI",
          status: :invalid,
          detail: "Configured OPENAI_API_KEY failed verification checks.",
          remediation: "Set a valid `OPENAI_API_KEY` (typically prefixed with `sk-`) and retry verification.",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp failing_provider_credential_report do
    %{
      checked_at: @checked_at,
      status: :invalid,
      credentials: [
        %{
          provider: :anthropic,
          name: "Anthropic",
          status: :not_set,
          detail: "No ANTHROPIC_API_KEY credential is configured.",
          remediation: "Set `ANTHROPIC_API_KEY` and retry verification.",
          checked_at: @checked_at
        },
        %{
          provider: :openai,
          name: "OpenAI",
          status: :invalid,
          detail: "Configured OPENAI_API_KEY failed verification checks.",
          remediation: "Set a valid `OPENAI_API_KEY` (typically prefixed with `sk-`) and retry verification.",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp passing_github_credential_report do
    %{
      checked_at: @checked_at,
      status: :ready,
      owner_context: "owner@example.com",
      paths: [
        %{
          path: :github_app,
          name: "GitHub App",
          status: :ready,
          previous_status: :not_configured,
          transition: "Not configured -> Ready",
          owner_context: "owner@example.com",
          repository_access: :confirmed,
          repositories: ["owner/repo-one"],
          detail: "GitHub App credentials are valid and repository access is confirmed.",
          remediation: "Credential path is ready.",
          validated_at: @checked_at,
          checked_at: @checked_at
        },
        %{
          path: :pat,
          name: "Personal Access Token (PAT)",
          status: :not_configured,
          previous_status: :not_configured,
          transition: "Not configured -> Not configured",
          owner_context: "owner@example.com",
          repository_access: :unconfirmed,
          repositories: [],
          detail: "No GitHub personal access token fallback is configured (`GITHUB_PAT`).",
          remediation: "Set `GITHUB_PAT` and retry validation.",
          error_type: "github_pat_not_configured",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp mixed_github_credential_report do
    %{
      checked_at: @checked_at,
      status: :ready,
      owner_context: "owner@example.com",
      paths: [
        %{
          path: :github_app,
          name: "GitHub App",
          status: :invalid,
          previous_status: :not_configured,
          transition: "Not configured -> Invalid",
          owner_context: "owner@example.com",
          repository_access: :unconfirmed,
          repositories: [],
          detail: "GitHub App credentials are configured but repository access could not be confirmed.",
          remediation: "Grant repository access for this owner context and retry validation.",
          error_type: "github_app_repository_access_unverified",
          checked_at: @checked_at
        },
        %{
          path: :pat,
          name: "Personal Access Token (PAT)",
          status: :ready,
          previous_status: :not_configured,
          transition: "Not configured -> Ready",
          owner_context: "owner@example.com",
          repository_access: :confirmed,
          repositories: ["owner/repo-one", "owner/repo-two"],
          detail: "GitHub PAT fallback is valid and confirms repository access.",
          remediation: "Credential path is ready.",
          validated_at: @checked_at,
          checked_at: @checked_at
        }
      ]
    }
  end

  defp failing_github_credential_report do
    %{
      checked_at: @checked_at,
      status: :blocked,
      owner_context: "owner@example.com",
      paths: [
        %{
          path: :github_app,
          name: "GitHub App",
          status: :invalid,
          previous_status: :not_configured,
          transition: "Not configured -> Invalid",
          owner_context: "owner@example.com",
          repository_access: :unconfirmed,
          repositories: [],
          detail: "Configured GitHub App credentials failed validation.",
          remediation: "Set valid GitHub App credentials and retry validation.",
          error_type: "github_app_credentials_invalid",
          checked_at: @checked_at
        },
        %{
          path: :pat,
          name: "Personal Access Token (PAT)",
          status: :invalid,
          previous_status: :not_configured,
          transition: "Not configured -> Invalid",
          owner_context: "owner@example.com",
          repository_access: :unconfirmed,
          repositories: [],
          detail: "Configured GitHub PAT failed validation.",
          remediation: "Set a valid `GITHUB_PAT` and retry validation.",
          error_type: "github_pat_credentials_invalid",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp redirect_path({path, _flash}) when is_binary(path), do: path
  defp redirect_path(path) when is_binary(path), do: path

  defp reset_owner_state! do
    Ecto.Adapters.SQL.query!(Repo, "TRUNCATE TABLE users RESTART IDENTITY CASCADE", [])
  end
end
