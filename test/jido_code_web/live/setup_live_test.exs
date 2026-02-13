defmodule JidoCodeWeb.SetupLiveTest do
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    original_loader = Application.get_env(:jido_code, :system_config_loader, :__missing__)
    original_saver = Application.get_env(:jido_code, :system_config_saver, :__missing__)
    original_config = Application.get_env(:jido_code, :system_config, :__missing__)

    on_exit(fn ->
      restore_env(:system_config_loader, original_loader)
      restore_env(:system_config_saver, original_saver)
      restore_env(:system_config, original_config)
    end)

    Application.delete_env(:jido_code, :system_config_loader)
    Application.delete_env(:jido_code, :system_config_saver)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 1,
      onboarding_state: %{}
    })

    :ok
  end

  test "persists step progression and resumes from the last incomplete step", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Prerequisite checks passed"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 2")

    assert %{
             onboarding_step: 2,
             onboarding_state: %{"1" => %{"validated_note" => "Prerequisite checks passed"}}
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
end
