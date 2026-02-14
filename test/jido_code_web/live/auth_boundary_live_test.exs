defmodule JidoCodeWeb.AuthBoundaryLiveTest do
  use JidoCodeWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias AshAuthentication.{Info, Strategy}
  alias AshAuthentication.TokenResource.Actions
  alias JidoCode.Accounts.Token
  alias JidoCode.Accounts.User

  test "unauthenticated dashboard access is denied and routed to auth entry flow", %{conn: conn} do
    log =
      capture_log([level: :warning], fn ->
        assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/dashboard")
        Logger.flush()
      end)

    assert log =~ "auth_boundary_check"
    assert log =~ "outcome=deny"
    assert log =~ "live_view=JidoCodeWeb.DashboardLive"
    assert log =~ "reason=missing_or_expired_session"
  end

  test "authenticated owner session resolves dashboard and logs allow boundary outcome", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, _session_token} = authenticate_owner_conn("owner@example.com", "owner-password-123")

    log =
      capture_log([level: :warning], fn ->
        {:ok, dashboard_view, _html} = live(authed_conn, ~p"/dashboard", on_error: :warn)
        assert has_element?(dashboard_view, "h1", "Dashboard")
        assert has_element?(dashboard_view, "p", "Welcome, owner@example.com")
        Logger.flush()
      end)

    assert log =~ "auth_boundary_check"
    assert log =~ "outcome=allow"
    assert log =~ "live_view=JidoCodeWeb.DashboardLive"
    assert log =~ "reason=owner_session_present"
  end

  test "revoked session context denies dashboard access and does not render protected data", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, session_token} = authenticate_owner_conn("owner@example.com", "owner-password-123")
    assert is_binary(session_token)
    assert :ok = Actions.revoke(Token, session_token)

    log =
      capture_log([level: :warning], fn ->
        assert {:error, {:redirect, %{to: "/sign-in"}}} = live(authed_conn, ~p"/dashboard")
        Logger.flush()
      end)

    denied_response = authed_conn |> recycle() |> get(~p"/dashboard")
    assert redirected_to(denied_response, 302) == "/sign-in"

    sign_in_html =
      denied_response
      |> recycle()
      |> get(~p"/sign-in")
      |> html_response(200)

    refute sign_in_html =~ "Welcome, owner@example.com"
    assert log =~ "auth_boundary_check"
    assert log =~ "outcome=deny"
    assert log =~ "reason=missing_or_expired_session"
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
end
