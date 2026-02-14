defmodule JidoCodeWeb.AshTypescriptRpcControllerTest do
  use JidoCodeWeb.ConnCase, async: true

  alias AshAuthentication.{Info, Strategy}
  alias AshAuthentication.TokenResource.Actions
  alias JidoCode.Accounts.Token
  alias JidoCode.Accounts.User

  @run_action_params %{"action" => "rpc_list_repositories", "fields" => ["id"]}

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

  defp issue_bearer_token do
    unique_suffix = System.unique_integer([:positive])
    email = "rpc-bearer-#{unique_suffix}@example.com"
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
    |> Map.get(:__metadata__, %{})
    |> Map.fetch!(:token)
  end
end
