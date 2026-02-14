defmodule JidoCodeWeb.AshTypescriptRpcController do
  use JidoCodeWeb, :controller

  require Logger

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User

  @api_key_audit_event [:jido_code, :rpc, :api_key, :used]
  @api_key_prefix "agentjido_"
  @rpc_auth_mode_policy_event "rpc_auth_mode_policy_decision"
  @all_auth_modes ["anonymous", "session", "bearer", "api_key"]
  @default_action_auth_mode_policy %{
    require_actor?: false,
    allowed_auth_modes: @all_auth_modes
  }
  @action_auth_mode_policies %{
    "rpc_list_repositories_session_or_bearer" => %{
      require_actor?: true,
      allowed_auth_modes: ["session", "bearer"]
    }
  }

  def run(conn, params) do
    execute_rpc(conn, params, fn request_conn, request_params ->
      :jido_code
      |> AshTypescript.Rpc.run_action(request_conn, request_params)
      |> normalize_error_response()
      |> attach_execution_identifiers(request_conn, request_params)
    end)
  end

  def validate(conn, params) do
    execute_rpc(conn, params, fn request_conn, request_params ->
      :jido_code
      |> AshTypescript.Rpc.validate_action(request_conn, request_params)
      |> normalize_error_response()
    end)
  end

  defp execute_rpc(conn, params, rpc_callback) do
    action_name = params |> map_get(:action, "action") |> normalize_optional_string()

    case resolve_rpc_auth(conn) do
      {:error, auth_mode} ->
        log_auth_mode_policy_decision(conn, action_name, auth_mode, "deny", "invalid_authentication", nil, nil)
        json(conn, auth_failure_response(auth_mode))

      {:ok, conn, auth_mode, actor} ->
        case authorize_action_auth_mode(action_name, auth_mode, actor) do
          {:ok, action_auth_mode_policy} ->
            log_auth_mode_policy_decision(
              conn,
              action_name,
              auth_mode,
              "allow",
              "authorized",
              action_auth_mode_policy,
              actor
            )

            maybe_record_api_key_audit(conn, actor, auth_mode)

            result =
              rpc_callback.(conn, params)
              |> attach_actor_auth_mode(auth_mode)

            json(conn, result)

          {:error, reason, action_auth_mode_policy} ->
            log_auth_mode_policy_decision(
              conn,
              action_name,
              auth_mode,
              "deny",
              reason,
              action_auth_mode_policy,
              actor
            )

            json(conn, action_auth_mode_failure_response(auth_mode, action_name, reason, action_auth_mode_policy))
        end
    end
  end

  defp authorize_action_auth_mode(action_name, auth_mode, actor) do
    action_auth_mode_policy = resolve_action_auth_mode_policy(action_name)
    require_actor? = Map.get(action_auth_mode_policy, :require_actor?, false)
    allowed_auth_modes = Map.get(action_auth_mode_policy, :allowed_auth_modes, @all_auth_modes)
    actor_present? = is_map(actor)

    cond do
      require_actor? and not actor_present? ->
        {:error, "missing_actor_context", action_auth_mode_policy}

      auth_mode not in allowed_auth_modes ->
        {:error, "auth_mode_not_allowed_for_action", action_auth_mode_policy}

      true ->
        {:ok, action_auth_mode_policy}
    end
  end

  defp resolve_action_auth_mode_policy(action_name) when is_binary(action_name) do
    Map.get(@action_auth_mode_policies, action_name, @default_action_auth_mode_policy)
  end

  defp resolve_action_auth_mode_policy(_action_name), do: @default_action_auth_mode_policy

  defp log_auth_mode_policy_decision(
         conn,
         action_name,
         auth_mode,
         decision,
         reason,
         action_auth_mode_policy,
         actor
       ) do
    action_auth_mode_policy = action_auth_mode_policy || %{}

    policy_allowed_auth_modes =
      action_auth_mode_policy
      |> Map.get(:allowed_auth_modes, [])
      |> Enum.join(",")

    policy_requires_actor = Map.get(action_auth_mode_policy, :require_actor?, false)
    actor_present? = is_map(actor)
    endpoint = conn.request_path
    method = conn.method
    normalized_action_name = action_name || "unknown"
    normalized_auth_mode = auth_mode || "unknown"
    log_level = if decision == "deny", do: :warning, else: :info

    Logger.log(
      log_level,
      "#{@rpc_auth_mode_policy_event} endpoint=#{endpoint} method=#{method} action=#{normalized_action_name} auth_mode=#{normalized_auth_mode} decision=#{decision} reason=#{reason} policy_require_actor=#{policy_requires_actor} policy_allowed_modes=#{policy_allowed_auth_modes} actor_present=#{actor_present?}"
    )
  end

  defp resolve_rpc_auth(conn) do
    case rpc_auth_credential(conn) do
      {:bearer, _token} ->
        resolve_bearer_auth(conn)

      {:api_key, api_key} ->
        resolve_api_key_auth(conn, api_key)

      :none ->
        {:ok, conn, resolved_non_bearer_auth_mode(conn), Ash.PlugHelpers.get_actor(conn)}
    end
  end

  defp resolve_bearer_auth(conn) do
    case bearer_actor(conn) do
      nil ->
        {:error, "bearer"}

      actor ->
        {:ok, assign_actor(conn, actor), "bearer", actor}
    end
  end

  defp resolve_api_key_auth(conn, api_key) do
    strategy = Info.strategy!(User, :api_key)

    opts = [
      tenant: Ash.PlugHelpers.get_tenant(conn),
      context: Ash.PlugHelpers.get_context(conn) || %{}
    ]

    case Strategy.action(strategy, :sign_in, %{"api_key" => api_key}, opts) do
      {:ok, actor} ->
        {:ok, assign_actor(conn, actor), "api_key", actor}

      {:error, _error} ->
        {:error, "api_key"}
    end
  end

  defp assign_actor(conn, actor) do
    conn
    |> Plug.Conn.assign(:current_user, actor)
    |> AshAuthentication.Plug.Helpers.set_actor(:user)
  end

  defp rpc_auth_credential(conn) do
    case authorization_header_credential(conn) do
      {:ok, credential} -> credential
      :error -> x_api_key_credential(conn)
    end
  end

  defp authorization_header_credential(conn) do
    conn
    |> Plug.Conn.get_req_header("authorization")
    |> Enum.reduce_while(:error, fn header, _acc ->
      case parse_authorization_header(header) do
        :error -> {:cont, :error}
        credential -> {:halt, {:ok, credential}}
      end
    end)
  end

  defp parse_authorization_header(header) when is_binary(header) do
    case String.split(header, " ", parts: 2) do
      [scheme, token] ->
        token = String.trim(token)

        if token == "" do
          :error
        else
          parse_authorization_token(String.downcase(scheme), token)
        end

      _ ->
        :error
    end
  end

  defp parse_authorization_token("bearer", token) do
    if api_key_token?(token), do: {:api_key, token}, else: {:bearer, token}
  end

  defp parse_authorization_token("apikey", token), do: {:api_key, token}
  defp parse_authorization_token("api-key", token), do: {:api_key, token}
  defp parse_authorization_token(_scheme, _token), do: :error

  defp x_api_key_credential(conn) do
    conn
    |> Plug.Conn.get_req_header("x-api-key")
    |> Enum.find_value(:none, fn api_key ->
      normalized_api_key = String.trim(api_key)
      if normalized_api_key == "", do: false, else: {:api_key, normalized_api_key}
    end)
  end

  defp api_key_token?(token), do: String.starts_with?(token, @api_key_prefix)

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

  defp maybe_record_api_key_audit(conn, actor, "api_key") when is_map(actor) do
    measurements = %{count: 1, usage_timestamp: System.system_time(:millisecond)}

    metadata = %{
      endpoint: conn.request_path,
      method: conn.method,
      actor_id: Map.get(actor, :id),
      api_key_id: actor_api_key_id(actor)
    }

    :telemetry.execute(@api_key_audit_event, measurements, metadata)

    Logger.info("api_key_rpc_audit=#{inspect(Map.merge(metadata, %{usage_timestamp: measurements.usage_timestamp}))}")
  end

  defp maybe_record_api_key_audit(_conn, _actor, _auth_mode), do: :ok

  defp actor_api_key_id(actor) when is_map(actor) do
    actor
    |> Map.get(:__metadata__, %{})
    |> Map.get(:api_key)
    |> case do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp actor_api_key_id(_actor), do: nil

  defp auth_failure_response("api_key"), do: api_key_auth_failure_response()
  defp auth_failure_response(auth_mode), do: bearer_auth_failure_response(auth_mode)

  defp action_auth_mode_failure_response(
         auth_mode,
         action_name,
         reason,
         action_auth_mode_policy
       ) do
    allowed_auth_modes = Map.get(action_auth_mode_policy, :allowed_auth_modes, @all_auth_modes)

    %{
      success: false,
      errors: [
        %{
          type: "authorization_failed",
          short_message: "Authorization failed",
          message: auth_mode_failure_message(reason),
          vars: %{},
          fields: [],
          path: [],
          details: %{
            reason: reason,
            action: action_name,
            actor_auth_mode: auth_mode,
            allowed_auth_modes: allowed_auth_modes
          }
        }
      ]
    }
    |> attach_actor_auth_mode(auth_mode)
  end

  defp auth_mode_failure_message("missing_actor_context") do
    "Actor context is required for this RPC action."
  end

  defp auth_mode_failure_message("auth_mode_not_allowed_for_action") do
    "The resolved authentication mode is not allowed for this RPC action."
  end

  defp auth_mode_failure_message(_reason) do
    "Authorization failed for this RPC action."
  end

  defp api_key_auth_failure_response do
    %{
      success: false,
      errors: [
        %{
          type: "authorization_failed",
          short_message: "Authorization failed",
          message: "API key is invalid, expired, or revoked.",
          vars: %{},
          fields: [],
          path: [],
          details: %{reason: "invalid_expired_or_revoked_api_key"}
        }
      ]
    }
    |> attach_actor_auth_mode("api_key")
  end

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
      if is_map(meta),
        do: Map.put(meta, :actor_auth_mode, auth_mode),
        else: %{actor_auth_mode: auth_mode}
    end)
  end

  defp normalize_error_response(result) when is_map(result) do
    success = map_get(result, :success, "success")
    errors = map_get(result, :errors, "errors")

    if success == false and is_list(errors) do
      normalized_errors = Enum.map(errors, &normalize_rpc_error/1)
      put_map_value(result, :errors, "errors", normalized_errors)
    else
      result
    end
  end

  defp normalize_error_response(result), do: result

  defp normalize_rpc_error(error) when is_map(error) do
    case map_get(error, :type, "type") do
      "action_not_found" ->
        action_name =
          error
          |> map_get(:vars, "vars", %{})
          |> map_get(:action_name, "action_name")

        error
        |> put_map_value(:type, "type", "contract_mismatch")
        |> put_map_value(:short_message, "short_message", "Contract mismatch")
        |> put_map_value(
          :message,
          "message",
          "RPC action %{action_name} does not match the public action contract"
        )
        |> Map.update(
          map_key(error, :vars, "vars"),
          map_default(error, :vars, "vars", %{action_name: action_name}),
          fn vars ->
            if is_map(vars) do
              put_map_value(vars, :action_name, "action_name", action_name)
            else
              %{action_name: action_name}
            end
          end
        )
        |> Map.update(
          map_key(error, :details, "details"),
          map_default(error, :details, "details", %{
            reason: "unknown_action",
            original_type: "action_not_found"
          }),
          fn details ->
            if is_map(details) do
              details
              |> put_map_value(:reason, "reason", "unknown_action")
              |> put_map_value(
                :original_type,
                "original_type",
                map_get(details, :original_type, "original_type", "action_not_found")
              )
            else
              %{reason: "unknown_action", original_type: "action_not_found"}
            end
          end
        )

      _other ->
        error
    end
  end

  defp normalize_rpc_error(error), do: error

  defp attach_execution_identifiers(result, conn, params) when is_map(result) do
    execution_identifiers =
      %{}
      |> maybe_put_identifier(
        :action_identifier,
        params |> map_get(:action, "action") |> normalize_optional_string()
      )
      |> maybe_put_identifier(
        :request_identifier,
        conn |> Plug.Conn.get_resp_header("x-request-id") |> List.first() |> normalize_optional_string()
      )

    if map_size(execution_identifiers) == 0 do
      result
    else
      meta_key = map_key(result, :meta, "meta")

      Map.update(result, meta_key, execution_identifiers, fn meta ->
        if is_map(meta), do: Map.merge(meta, execution_identifiers), else: execution_identifiers
      end)
    end
  end

  defp attach_execution_identifiers(result, _conn, _params), do: result

  defp maybe_put_identifier(map, _key, nil), do: map
  defp maybe_put_identifier(map, key, value), do: Map.put(map, key, value)

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp map_get(map, atom_key, string_key, default \\ nil) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_key(map, atom_key, string_key) when is_map(map) do
    if Map.has_key?(map, string_key), do: string_key, else: atom_key
  end

  defp map_default(map, atom_key, string_key, default) when is_map(map) do
    if Map.has_key?(map, atom_key) or Map.has_key?(map, string_key), do: %{}, else: default
  end

  defp put_map_value(map, atom_key, string_key, value) when is_map(map) do
    Map.put(map, map_key(map, atom_key, string_key), value)
  end
end
