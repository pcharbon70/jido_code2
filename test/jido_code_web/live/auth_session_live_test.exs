defmodule JidoCodeWeb.AuthSessionLiveTest do
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User

  test "valid owner credentials create a browser session for protected route navigation", %{
    conn: conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {:ok, sign_in_view, _html} = live(conn, ~p"/sign-in", on_error: :warn)

    sign_in_view
    |> form("form[action='/auth/user/password/sign_in']", %{
      "user" => %{"email" => "owner@example.com", "password" => "owner-password-123"}
    })
    |> render_submit()

    auth_redirect_path =
      sign_in_view
      |> assert_redirect()
      |> redirect_path()

    auth_response = build_conn() |> get(auth_redirect_path)
    assert redirected_to(auth_response, 302) == "/"

    assert auth_response
           |> get_resp_header("set-cookie")
           |> Enum.any?(&String.contains?(&1, "_jido_code_key="))

    authed_conn = recycle(auth_response)

    {:ok, dashboard_view, _dashboard_html} = live(authed_conn, ~p"/dashboard", on_error: :warn)
    assert has_element?(dashboard_view, "h1", "Dashboard")
    assert has_element?(dashboard_view, "p", "Welcome, owner@example.com")

    {:ok, settings_view, _settings_html} = live(recycle(authed_conn), ~p"/settings", on_error: :warn)
    assert has_element?(settings_view, "h1", "Settings")
  end

  test "invalid owner credentials deny session creation and return a typed authentication error", %{
    conn: conn
  } do
    register_owner("owner@example.com", "owner-password-123")
    strategy = Info.strategy!(User, :password)

    assert {:error, %AshAuthentication.Errors.AuthenticationFailed{} = auth_error} =
             Strategy.action(
               strategy,
               :sign_in,
               %{"email" => "owner@example.com", "password" => "wrong-password-123"},
               context: %{token_type: :sign_in}
             )

    assert match?(%AshAuthentication.Strategy.Password{}, auth_error.strategy)

    {:ok, sign_in_view, _html} = live(conn, ~p"/sign-in", on_error: :warn)

    sign_in_view
    |> form("form[action='/auth/user/password/sign_in']", %{
      "user" => %{"email" => "owner@example.com", "password" => "wrong-password-123"}
    })
    |> render_submit()

    :ok = refute_redirected(sign_in_view)
    assert render(sign_in_view) =~ "Email or password was incorrect"

    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), ~p"/dashboard")
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

  defp redirect_path({path, _flash}) when is_binary(path), do: path
  defp redirect_path(path) when is_binary(path), do: path
end
