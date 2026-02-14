defmodule JidoCodeWeb.SecuritySettingsLiveTest do
  use JidoCodeWeb.ConnCase, async: false

  require Ash.Query

  import Phoenix.LiveViewTest

  alias AshAuthentication.{Info, Jwt, Strategy}
  alias JidoCode.Accounts
  alias JidoCode.Accounts.ApiKey
  alias JidoCode.Accounts.User

  @run_action_params %{"action" => "rpc_list_repositories", "fields" => ["id"]}

  test "security tab exposes expiry metadata and revocation controls that invalidate bearer and api key auth",
       %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, session_token, owner} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    %{api_key: api_key, api_key_record: api_key_record} = issue_api_key(owner)

    {:ok, %{"jti" => session_jti}} = Jwt.peek(session_token)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings/security", on_error: :warn)

    assert has_element?(view, "#settings-security-token-expires-at-#{session_jti}")
    assert has_element?(view, "#settings-security-api-key-expires-at-#{api_key_record.id}")

    view
    |> element("#settings-security-revoke-token-#{session_jti}")
    |> render_click()

    assert has_element?(view, "#settings-security-token-status-#{session_jti}", "Revoked")
    refute has_element?(view, "#settings-security-token-revoked-at-#{session_jti}", "Not revoked")

    bearer_response =
      build_conn()
      |> put_req_header("authorization", "Bearer #{session_token}")
      |> post(~p"/rpc/run", @run_action_params)
      |> json_response(200)

    assert bearer_response["success"] == false

    assert get_in(bearer_response, ["errors", Access.at(0), "details", "reason"]) ==
             "invalid_expired_or_revoked_bearer_token"

    view
    |> element("#settings-security-revoke-api-key-#{api_key_record.id}")
    |> render_click()

    assert has_element?(view, "#settings-security-api-key-status-#{api_key_record.id}", "Revoked")

    refute has_element?(
             view,
             "#settings-security-api-key-revoked-at-#{api_key_record.id}",
             "Not revoked"
           )

    api_key_response =
      build_conn()
      |> put_req_header("x-api-key", api_key)
      |> post(~p"/rpc/validate", @run_action_params)
      |> json_response(200)

    assert api_key_response["success"] == false

    assert get_in(api_key_response, ["errors", Access.at(0), "details", "reason"]) ==
             "invalid_expired_or_revoked_api_key"

    assert has_element?(view, "#settings-security-audit-log", "revoked at")
  end

  test "failed revocation keeps state unchanged and returns typed recovery instructions", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token, owner} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    %{api_key: api_key, api_key_record: api_key_record} = issue_api_key(owner)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings/security", on_error: :warn)

    view
    |> element("#settings-security-revoke-api-key-#{api_key_record.id}")
    |> render_click()

    revoked_api_key = read_api_key!(api_key_record.id)
    assert %DateTime{} = revoked_api_key.revoked_at

    view
    |> element("#settings-security-revoke-api-key-#{api_key_record.id}")
    |> render_click()

    assert has_element?(
             view,
             "#settings-security-revocation-error-type",
             "api_key_already_revoked"
           )

    assert has_element?(view, "#settings-security-revocation-recovery", "already revoked")

    unchanged_api_key = read_api_key!(api_key_record.id)
    assert DateTime.compare(unchanged_api_key.revoked_at, revoked_api_key.revoked_at) == :eq

    api_key_response =
      build_conn()
      |> put_req_header("x-api-key", api_key)
      |> post(~p"/rpc/validate", @run_action_params)
      |> json_response(200)

    assert api_key_response["success"] == false

    assert get_in(api_key_response, ["errors", Access.at(0), "details", "reason"]) ==
             "invalid_expired_or_revoked_api_key"
  end

  test "security tab persists encrypted SecretRef metadata and never renders plaintext values", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token, _owner} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings/security", on_error: :warn)

    secret_name = "github/webhook_secret_#{System.unique_integer([:positive])}"
    plaintext_value = "very-secret-value-#{System.unique_integer([:positive])}"

    view
    |> form("#settings-security-secret-form", %{
      "security_secret" => %{
        "scope" => "integration",
        "name" => secret_name,
        "value" => plaintext_value
      }
    })
    |> render_submit()

    assert has_element?(view, "#settings-security-secret-metadata", secret_name)
    assert has_element?(view, "#settings-security-secret-metadata", "integration")
    refute has_element?(view, "#settings-security-secret-metadata", plaintext_value)
    refute has_element?(view, "#settings-security-secret-value[value='#{plaintext_value}']")
  end

  test "security tab blocks secret persistence with typed remediation when encryption config is missing",
       %{conn: _conn} do
    original_key = Application.get_env(:jido_code, :secret_ref_encryption_key, :__missing__)

    on_exit(fn ->
      restore_env(:secret_ref_encryption_key, original_key)
    end)

    Application.delete_env(:jido_code, :secret_ref_encryption_key)

    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token, _owner} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings/security", on_error: :warn)

    secret_name = "missing/encryption_#{System.unique_integer([:positive])}"

    view
    |> form("#settings-security-secret-form", %{
      "security_secret" => %{
        "scope" => "integration",
        "name" => secret_name,
        "value" => "plaintext-that-must-not-persist"
      }
    })
    |> render_submit()

    assert has_element?(
             view,
             "#settings-security-secret-error-type",
             "secret_encryption_unavailable"
           )

    assert has_element?(
             view,
             "#settings-security-secret-error-recovery",
             "JIDO_CODE_SECRET_REF_ENCRYPTION_KEY"
           )

    refute has_element?(view, "#settings-security-secret-metadata", secret_name)
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
    {recycle(auth_response), session_token, owner}
  end

  defp issue_api_key(owner) do
    expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

    {:ok, api_key_record} =
      Ash.create(
        ApiKey,
        %{user_id: owner.id, expires_at: expires_at},
        domain: Accounts,
        authorize?: false
      )

    api_key =
      api_key_record
      |> Map.get(:__metadata__, %{})
      |> Map.fetch!(:plaintext_api_key)

    %{api_key: api_key, api_key_record: api_key_record}
  end

  defp read_api_key!(api_key_id) do
    query =
      ApiKey
      |> Ash.Query.filter(id == ^api_key_id)
      |> Ash.Query.limit(1)

    {:ok, [api_key]} = Ash.read(query, domain: Accounts, authorize?: false)

    api_key
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

  defp restore_env(key, :__missing__) do
    Application.delete_env(:jido_code, key)
  end

  defp restore_env(key, value) do
    Application.put_env(:jido_code, key, value)
  end
end
