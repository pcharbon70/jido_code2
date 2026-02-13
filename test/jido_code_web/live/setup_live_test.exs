defmodule JidoCodeWeb.SetupLiveTest do
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @checked_at ~U[2026-02-13 12:34:56Z]

  setup do
    original_loader = Application.get_env(:jido_code, :system_config_loader, :__missing__)
    original_saver = Application.get_env(:jido_code, :system_config_saver, :__missing__)
    original_config = Application.get_env(:jido_code, :system_config, :__missing__)
    original_checker = Application.get_env(:jido_code, :setup_prerequisite_checker, :__missing__)
    original_timeout = Application.get_env(:jido_code, :setup_prerequisite_timeout_ms, :__missing__)

    on_exit(fn ->
      restore_env(:system_config_loader, original_loader)
      restore_env(:system_config_saver, original_saver)
      restore_env(:system_config, original_config)
      restore_env(:setup_prerequisite_checker, original_checker)
      restore_env(:setup_prerequisite_timeout_ms, original_timeout)
    end)

    Application.delete_env(:jido_code, :system_config_loader)
    Application.delete_env(:jido_code, :system_config_saver)
    Application.delete_env(:jido_code, :setup_prerequisite_timeout_ms)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 1,
      onboarding_state: %{}
    })

    Application.put_env(:jido_code, :setup_prerequisite_checker, fn _timeout_ms ->
      passing_prerequisite_report()
    end)

    :ok
  end

  test "step 1 shows timestamped prerequisite checks and persists progression on success", %{conn: conn} do
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

    view
    |> form("#onboarding-step-form", %{"step" => %{"validated_note" => "Owner account confirmed"}})
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 3")
    assert has_element?(view, "#validated-state-step-1", "Prerequisite checks passed")
    assert has_element?(view, "#validated-state-step-2", "Owner account confirmed")

    {:ok, resumed_view, _html} = live(build_conn(), ~p"/setup", on_error: :warn)

    assert has_element?(resumed_view, "#resolved-onboarding-step", "Step 3")
    assert has_element?(resumed_view, "#validated-state-step-1", "Prerequisite checks passed")
    assert has_element?(resumed_view, "#validated-state-step-2", "Owner account confirmed")
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

  test "step 1 timeout keeps onboarding blocked and does not persist downstream data", %{conn: conn} do
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
      onboarding_step: 2,
      onboarding_state: %{"1" => %{"validated_note" => "Prerequisite checks passed"}}
    })

    Application.put_env(:jido_code, :system_config_saver, fn _config ->
      {:error, :database_unreachable}
    end)

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)
    assert has_element?(view, "#resolved-onboarding-step", "Step 2")

    view
    |> form("#onboarding-step-form", %{"step" => %{"validated_note" => "Owner account confirmed"}})
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 2")
    assert has_element?(view, "#setup-save-error", "safely retry this step")
    assert has_element?(view, "#validated-state-step-1", "Prerequisite checks passed")

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 2
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)

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
end
