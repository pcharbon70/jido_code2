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
    original_runtime_mode = Application.get_env(:jido_code, :runtime_mode, :__missing__)

    original_timeout =
      Application.get_env(:jido_code, :setup_prerequisite_timeout_ms, :__missing__)

    on_exit(fn ->
      restore_env(:system_config_loader, original_loader)
      restore_env(:system_config_saver, original_saver)
      restore_env(:system_config, original_config)
      restore_env(:setup_prerequisite_checker, original_checker)
      restore_env(:setup_prerequisite_timeout_ms, original_timeout)
      restore_env(:runtime_mode, original_runtime_mode)
    end)

    Application.delete_env(:jido_code, :system_config_loader)
    Application.delete_env(:jido_code, :system_config_saver)
    Application.delete_env(:jido_code, :setup_prerequisite_timeout_ms)
    Application.put_env(:jido_code, :runtime_mode, :test)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 1,
      onboarding_state: %{}
    })

    Application.put_env(:jido_code, :setup_prerequisite_checker, fn _timeout_ms ->
      passing_prerequisite_report()
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

  defp redirect_path({path, _flash}) when is_binary(path), do: path
  defp redirect_path(path) when is_binary(path), do: path

  defp reset_owner_state! do
    Ecto.Adapters.SQL.query!(Repo, "TRUNCATE TABLE users RESTART IDENTITY CASCADE", [])
  end
end
