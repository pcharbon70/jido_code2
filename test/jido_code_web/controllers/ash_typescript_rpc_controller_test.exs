defmodule JidoCodeWeb.AshTypescriptRpcControllerTest do
  use JidoCodeWeb.ConnCase, async: true

  alias AshAuthentication.{Info, Strategy}
  alias AshAuthentication.TokenResource.Actions
  alias JidoCode.Accounts.ApiKey
  alias JidoCode.Accounts.Token
  alias JidoCode.Accounts.User

  @api_key_audit_event [:jido_code, :rpc, :api_key, :used]
  @run_action_params %{"action" => "rpc_list_repositories", "fields" => ["id"]}
  @invalid_validate_action_params %{"fields" => ["id"]}
  @unknown_run_action_params %{"action" => "rpc_unknown_action", "fields" => ["id"]}
  @unknown_validate_action_params %{"action" => "rpc_unknown_action", "fields" => ["id"]}

  test "valid bearer token executes rpc action and returns auth mode metadata", %{conn: conn} do
    bearer_token = issue_bearer_token()

    response =
      conn
      |> put_req_header("authorization", "Bearer #{bearer_token}")
      |> post(~p"/rpc/run", @run_action_params)
      |> json_response(200)

    assert response["success"] == true
    assert is_list(response["data"])
    assert get_in(response, ["meta", "actor_auth_mode"]) == "bearer"
    refute Jason.encode!(response) =~ bearer_token
  end

  test "invalid bearer token returns typed authorization failure", %{conn: conn} do
    invalid_bearer_token = "invalid-bearer-token"

    response =
      conn
      |> put_req_header("authorization", "Bearer #{invalid_bearer_token}")
      |> post(~p"/rpc/run", @run_action_params)
      |> json_response(200)

    assert response["success"] == false
    assert get_in(response, ["meta", "actor_auth_mode"]) == "bearer"

    [error | _] = response["errors"]
    assert error["type"] == "authorization_failed"
    assert error["details"]["reason"] == "invalid_expired_or_revoked_bearer_token"
    refute Jason.encode!(response) =~ invalid_bearer_token
  end

  test "revoked bearer token returns typed authorization failure", %{conn: conn} do
    bearer_token = issue_bearer_token()
    assert :ok = Actions.revoke(Token, bearer_token)

    response =
      conn
      |> put_req_header("authorization", "Bearer #{bearer_token}")
      |> post(~p"/rpc/run", @run_action_params)
      |> json_response(200)

    assert response["success"] == false
    assert get_in(response, ["meta", "actor_auth_mode"]) == "bearer"

    [error | _] = response["errors"]
    assert error["type"] == "authorization_failed"
    assert error["details"]["reason"] == "invalid_expired_or_revoked_bearer_token"
    refute Jason.encode!(response) =~ bearer_token
  end

  test "valid api key validates rpc action and records audit metadata", %{conn: conn} do
    attach_api_key_audit_handler()
    %{api_key: api_key, owner: owner, api_key_record: api_key_record} = issue_api_key()

    response =
      conn
      |> put_req_header("authorization", "Bearer #{api_key}")
      |> post(~p"/rpc/validate", @run_action_params)
      |> json_response(200)

    assert response["success"] == true
    assert get_in(response, ["meta", "actor_auth_mode"]) == "api_key"
    refute Jason.encode!(response) =~ api_key

    assert_receive {:api_key_audit, event_name, measurements, metadata}
    assert event_name == @api_key_audit_event
    assert measurements.count == 1
    assert is_integer(measurements.usage_timestamp)
    assert metadata.endpoint == "/rpc/validate"
    assert metadata.method == "POST"
    assert metadata.actor_id == owner.id
    assert metadata.api_key_id == api_key_record.id
  end

  test "validate endpoint accepts action identifier and payload and returns typed success", %{
    conn: conn
  } do
    response =
      conn
      |> post(~p"/rpc/validate", @run_action_params)
      |> json_response(200)

    assert response["success"] == true
    assert get_in(response, ["meta", "actor_auth_mode"]) == "anonymous"
    assert response["errors"] in [nil, []]
    refute Map.has_key?(response, "data")
  end

  test "validate endpoint returns structured validation errors without execution payload", %{
    conn: conn
  } do
    response =
      conn
      |> post(~p"/rpc/validate", @invalid_validate_action_params)
      |> json_response(200)

    assert response["success"] == false
    assert get_in(response, ["meta", "actor_auth_mode"]) == "anonymous"
    refute Map.has_key?(response, "data")

    [error | _] = response["errors"]
    assert is_binary(error["type"])
    assert is_binary(error["message"])
    assert is_map(error["details"])
    assert is_list(error["fields"])
    assert is_list(error["path"])
  end

  test "validate endpoint returns typed contract mismatch when action is unknown", %{conn: conn} do
    response =
      conn
      |> post(~p"/rpc/validate", @unknown_validate_action_params)
      |> json_response(200)

    assert response["success"] == false
    assert get_in(response, ["meta", "actor_auth_mode"]) == "anonymous"
    refute Map.has_key?(response, "data")

    [error | _] = response["errors"]
    assert error["type"] == "contract_mismatch"
    assert error["details"]["reason"] == "unknown_action"
    assert error["details"]["original_type"] == "action_not_found"
  end

  test "run endpoint returns typed payload with execution identifiers across repeated calls", %{
    conn: conn
  } do
    first_response =
      conn
      |> post(~p"/rpc/run", @run_action_params)
      |> json_response(200)

    second_response =
      conn
      |> recycle()
      |> post(~p"/rpc/run", @run_action_params)
      |> json_response(200)

    assert first_response["success"] == true
    assert second_response["success"] == true
    assert is_list(first_response["data"])
    assert first_response["data"] == second_response["data"]
    assert get_in(first_response, ["meta", "actor_auth_mode"]) == "anonymous"
    assert get_in(first_response, ["meta", "action_identifier"]) == "rpc_list_repositories"
    assert get_in(second_response, ["meta", "action_identifier"]) == "rpc_list_repositories"

    first_request_identifier = get_in(first_response, ["meta", "request_identifier"])
    second_request_identifier = get_in(second_response, ["meta", "request_identifier"])
    assert is_binary(first_request_identifier) and first_request_identifier != ""
    assert is_binary(second_request_identifier) and second_request_identifier != ""
  end

  test "run endpoint returns typed contract mismatch taxonomy when action is unknown", %{
    conn: conn
  } do
    response =
      conn
      |> post(~p"/rpc/run", @unknown_run_action_params)
      |> json_response(200)

    assert response["success"] == false
    assert get_in(response, ["meta", "actor_auth_mode"]) == "anonymous"
    assert get_in(response, ["meta", "action_identifier"]) == "rpc_unknown_action"
    refute Map.has_key?(response, "data")

    request_identifier = get_in(response, ["meta", "request_identifier"])
    assert is_binary(request_identifier) and request_identifier != ""

    [error | _] = response["errors"]
    assert error["type"] == "contract_mismatch"
    assert error["details"]["reason"] == "unknown_action"
    assert error["details"]["original_type"] == "action_not_found"
    assert is_binary(error["message"])
    assert is_map(error["details"])
    assert is_list(error["fields"])
    assert is_list(error["path"])
  end

  test "valid api key executes rpc action through run endpoint", %{conn: conn} do
    %{api_key: api_key} = issue_api_key()

    response =
      conn
      |> put_req_header("authorization", "Bearer #{api_key}")
      |> post(~p"/rpc/run", @run_action_params)
      |> json_response(200)

    assert response["success"] == true
    assert is_list(response["data"])
    assert get_in(response, ["meta", "actor_auth_mode"]) == "api_key"
    refute Jason.encode!(response) =~ api_key
  end

  test "revoked api key returns typed authorization failure and performs no RPC action", %{
    conn: conn
  } do
    attach_api_key_audit_handler()
    %{api_key: api_key, api_key_record: api_key_record} = issue_api_key()
    assert :ok = Ash.destroy(api_key_record, authorize?: false)

    response =
      conn
      |> put_req_header("x-api-key", api_key)
      |> post(~p"/rpc/validate", @run_action_params)
      |> json_response(200)

    assert response["success"] == false
    assert get_in(response, ["meta", "actor_auth_mode"]) == "api_key"
    refute Map.has_key?(response, "data")

    [error | _] = response["errors"]
    assert error["type"] == "authorization_failed"
    assert error["details"]["reason"] == "invalid_expired_or_revoked_api_key"
    refute_receive {:api_key_audit, _event_name, _measurements, _metadata}
    refute Jason.encode!(response) =~ api_key
  end

  test "expired api key returns typed authorization failure", %{conn: conn} do
    expires_at = DateTime.add(DateTime.utc_now(), -60, :second)
    %{api_key: api_key} = issue_api_key(expires_at: expires_at)

    response =
      conn
      |> put_req_header("x-api-key", api_key)
      |> post(~p"/rpc/run", @run_action_params)
      |> json_response(200)

    assert response["success"] == false
    assert get_in(response, ["meta", "actor_auth_mode"]) == "api_key"

    [error | _] = response["errors"]
    assert error["type"] == "authorization_failed"
    assert error["details"]["reason"] == "invalid_expired_or_revoked_api_key"
    refute Jason.encode!(response) =~ api_key
  end

  defp issue_bearer_token do
    "rpc-bearer"
    |> register_owner()
    |> Map.get(:__metadata__, %{})
    |> Map.fetch!(:token)
  end

  defp issue_api_key(opts \\ []) do
    owner = register_owner("rpc-api-key")
    expires_at = Keyword.get(opts, :expires_at, DateTime.add(DateTime.utc_now(), 3600, :second))

    {:ok, api_key_record} =
      Ash.create(
        ApiKey,
        %{user_id: owner.id, expires_at: expires_at},
        authorize?: false
      )

    api_key =
      api_key_record
      |> Map.get(:__metadata__, %{})
      |> Map.fetch!(:plaintext_api_key)

    %{api_key: api_key, owner: owner, api_key_record: api_key_record}
  end

  defp register_owner(email_prefix) do
    unique_suffix = System.unique_integer([:positive])
    email = "#{email_prefix}-#{unique_suffix}@example.com"
    password = "owner-password-123"

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

    {:ok, signed_in_owner} =
      Strategy.action(
        strategy,
        :sign_in,
        %{"email" => email, "password" => password},
        context: %{token_type: :user}
      )

    signed_in_owner
  end

  defp attach_api_key_audit_handler do
    test_pid = self()
    handler_id = "rpc-api-key-audit-handler-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        @api_key_audit_event,
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:api_key_audit, event_name, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
