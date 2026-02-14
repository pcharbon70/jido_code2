defmodule JidoCodeWeb.AshTypescriptRpcController do
  use JidoCodeWeb, :controller

  def run(conn, params) do
    case resolve_bearer_auth(conn) do
      {:error, auth_mode} ->
        json(conn, bearer_auth_failure_response(auth_mode))

      {:ok, conn, auth_mode} ->
        result =
          :jido_code
          |> AshTypescript.Rpc.run_action(conn, params)
          |> attach_actor_auth_mode(auth_mode)

        json(conn, result)
    end
  end

  def validate(conn, params) do
    result = AshTypescript.Rpc.validate_action(:jido_code, conn, params)
    json(conn, result)
  end

  defp resolve_bearer_auth(conn) do
    case bearer_token(conn) do
      {:ok, _token} ->
        case bearer_actor(conn) do
          nil ->
            {:error, "bearer"}

          actor ->
            conn =
              conn
              |> Plug.Conn.assign(:current_user, actor)
              |> AshAuthentication.Plug.Helpers.set_actor(:user)

            {:ok, conn, "bearer"}
        end

      :error ->
        {:ok, conn, resolved_non_bearer_auth_mode(conn)}
    end
  end

  defp bearer_token(conn) do
    conn
    |> Plug.Conn.get_req_header("authorization")
    |> Enum.find_value(:error, fn header ->
      case String.split(header, " ", parts: 2) do
        [scheme, token] when scheme in ["Bearer", "bearer"] ->
          token = String.trim(token)
          if token == "", do: false, else: {:ok, token}

        _ ->
          false
      end
    end)
  end

  defp bearer_actor(conn) do
    conn
    |> with_cleared_assigns()
    |> AshAuthentication.Plug.Helpers.retrieve_from_bearer(:jido_code)
    |> Map.get(:assigns, %{})
    |> Map.get(:current_user)
  end

  defp with_cleared_assigns(%Plug.Conn{} = conn) do
    %Plug.Conn{conn | assigns: %{}}
  end

  defp resolved_non_bearer_auth_mode(conn) do
    actor = Ash.PlugHelpers.get_actor(conn)

    cond do
      api_key_actor?(actor) -> "api_key"
      is_nil(actor) -> "anonymous"
      true -> "session"
    end
  end

  defp api_key_actor?(actor) when is_map(actor) do
    actor
    |> Map.get(:__metadata__, %{})
    |> Map.get(:using_api_key?, false)
  end

  defp api_key_actor?(_actor), do: false

  defp bearer_auth_failure_response(auth_mode) do
    %{
      success: false,
      errors: [
        %{
          type: "authorization_failed",
          short_message: "Authorization failed",
          message: "Bearer token is invalid, expired, or revoked.",
          vars: %{},
          fields: [],
          path: [],
          details: %{reason: "invalid_expired_or_revoked_bearer_token"}
        }
      ]
    }
    |> attach_actor_auth_mode(auth_mode)
  end

  defp attach_actor_auth_mode(result, auth_mode) when is_map(result) do
    Map.update(result, :meta, %{actor_auth_mode: auth_mode}, fn meta ->
      if is_map(meta), do: Map.put(meta, :actor_auth_mode, auth_mode), else: %{actor_auth_mode: auth_mode}
    end)
  end
end
