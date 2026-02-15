defmodule JidoCodeWeb.AshTypescriptRpcController do
  use JidoCodeWeb, :controller

  require Logger

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User
  alias JidoCode.Security.LogRedactor

  @api_key_audit_event [:jido_code, :rpc, :api_key, :used]
  @api_key_prefix "agentjido_"
  @rpc_auth_mode_policy_event "rpc_auth_mode_policy_decision"
  @rpc_validation_redaction_event "rpc_validation_error_redaction_failed"
  @all_auth_modes ["anonymous", "session", "bearer", "api_key"]
  @validation_error_type "validation_error"
  @validation_error_default_message "RPC validation failed."
  @validation_error_default_short_message "Validation failed"
  @validation_redaction_failure_reason "validation_error_redaction_failed"
  @validation_reason_code_pattern ~r/[^a-zA-Z0-9._-]/
  @validation_safe_detail_keys [
    :suggestion,
    :hint,
    :expected,
    :expected_code,
    :allowed_fields,
    :expected_members,
    :expected_keys,
    :provided_keys,
    :disallowed_paths,
    :denied_paths
  ]
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
      |> normalize_validation_error_response()
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

  defp normalize_validation_error_response(result) when is_map(result) do
    success = map_get(result, :success, "success")
    errors = map_get(result, :errors, "errors")

    if success == false and is_list(errors) do
      case sanitize_and_redact_validation_errors(errors) do
        {:ok, sanitized_errors} ->
          put_map_value(result, :errors, "errors", sanitized_errors)

        {:error, reason} ->
          log_validation_redaction_failure(reason)
          generic_validation_error_response()
      end
    else
      result
    end
  end

  defp normalize_validation_error_response(result), do: result

  defp sanitize_and_redact_validation_errors(errors) when is_list(errors) do
    redactor = validation_error_redactor()

    errors
    |> Enum.reduce_while({:ok, []}, fn error, {:ok, acc} ->
      with {:ok, sanitized_error} <- sanitize_validation_error(error),
           {:ok, redacted_error} <- redact_validation_error(redactor, sanitized_error) do
        {:cont, {:ok, [redacted_error | acc]}}
      else
        {:error, _reason} = error_result ->
          {:halt, error_result}
      end
    end)
    |> case do
      {:ok, sanitized_errors} -> {:ok, Enum.reverse(sanitized_errors)}
      {:error, _reason} = error -> error
    end
  end

  defp sanitize_and_redact_validation_errors(_errors) do
    {:error, %{error_type: "redaction_invalid_payload"}}
  end

  defp sanitize_validation_error(error) when is_map(error) do
    normalized_type = normalize_validation_error_type(map_get(error, :type, "type"))
    reason_code = resolve_validation_reason_code(error, normalized_type)

    normalized_error = %{
      type: normalized_type,
      short_message:
        normalize_validation_error_message(
          map_get(error, :short_message, "short_message"),
          @validation_error_default_short_message
        ),
      message:
        normalize_validation_error_message(
          map_get(error, :message, "message"),
          @validation_error_default_message
        ),
      vars: %{},
      fields: normalize_validation_error_field_list(map_get(error, :fields, "fields", [])),
      path: normalize_validation_error_path(map_get(error, :path, "path", [])),
      details:
        normalize_validation_error_details(
          map_get(error, :details, "details", %{}),
          reason_code,
          normalized_type
        )
    }

    {:ok, normalized_error}
  end

  defp sanitize_validation_error(_error) do
    {:ok, generic_validation_error()}
  end

  defp redact_validation_error(redactor, error) when is_atom(redactor) and is_map(error) do
    try do
      case apply(redactor, :redact_event, [error]) do
        {:ok, redacted_error} when is_map(redacted_error) ->
          {:ok, redacted_error}

        {:error, reason} ->
          {:error, reason}

        _other ->
          {:error, %{error_type: "redaction_invalid_response", message: "Unexpected redactor response."}}
      end
    rescue
      exception ->
        {:error, %{error_type: "redaction_exception", message: Exception.message(exception)}}
    catch
      kind, _reason ->
        {:error, %{error_type: "redaction_#{kind}", message: "Redaction crashed unexpectedly."}}
    end
  end

  defp redact_validation_error(_redactor, _error) do
    {:error, %{error_type: "redaction_invalid_redactor"}}
  end

  defp normalize_validation_error_type(value) do
    case normalize_optional_string(value) do
      nil -> @validation_error_type
      normalized_type -> normalized_type
    end
  end

  defp normalize_validation_error_message(value, default_message) do
    case normalize_optional_string(value) do
      nil -> default_message
      normalized_message -> normalized_message
    end
  end

  defp normalize_validation_error_details(details, reason_code, normalized_type) when is_map(details) do
    original_type = details |> map_get(:original_type, "original_type") |> normalize_optional_string()

    sanitized_details =
      @validation_safe_detail_keys
      |> Enum.reduce(%{}, fn key, acc ->
        string_key = Atom.to_string(key)

        case map_get(details, key, string_key, :__missing__) do
          :__missing__ ->
            acc

          value ->
            if safe_validation_detail_value?(value) do
              put_map_value(acc, key, string_key, value)
            else
              acc
            end
        end
      end)
      |> put_map_value(:reason, "reason", reason_code)

    if is_binary(original_type) and original_type != "" and original_type != normalized_type do
      put_map_value(sanitized_details, :original_type, "original_type", original_type)
    else
      sanitized_details
    end
  end

  defp normalize_validation_error_details(_details, reason_code, _normalized_type) do
    %{reason: reason_code}
  end

  defp safe_validation_detail_value?(value) when is_binary(value), do: true
  defp safe_validation_detail_value?(value) when is_boolean(value) or is_number(value), do: true
  defp safe_validation_detail_value?(nil), do: true

  defp safe_validation_detail_value?(value) when is_list(value) do
    Enum.all?(value, fn
      item when is_binary(item) -> true
      item when is_boolean(item) or is_number(item) -> true
      item when is_atom(item) -> true
      nil -> true
      _other -> false
    end)
  end

  defp safe_validation_detail_value?(_value), do: false

  defp normalize_validation_error_field_list(value) when is_list(value) do
    value
    |> Enum.reduce([], fn item, acc ->
      case normalize_validation_field_value(item) do
        nil -> acc
        normalized_item -> [normalized_item | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp normalize_validation_error_field_list(_value), do: []

  defp normalize_validation_error_path(value) when is_list(value) do
    value
    |> Enum.reduce([], fn
      item, acc when is_integer(item) ->
        [item | acc]

      item, acc ->
        case normalize_validation_field_value(item) do
          nil -> acc
          normalized_item -> [normalized_item | acc]
        end
    end)
    |> Enum.reverse()
  end

  defp normalize_validation_error_path(_value), do: []

  defp normalize_validation_field_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_validation_field_value(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_validation_field_value()

  defp normalize_validation_field_value(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_validation_field_value(_value), do: nil

  defp resolve_validation_reason_code(error, normalized_type) when is_map(error) do
    details = map_get(error, :details, "details", %{})

    details_reason =
      if is_map(details),
        do: details |> map_get(:reason, "reason") |> normalize_optional_string(),
        else: nil

    details_reason
    |> case do
      nil -> normalized_type
      explicit_reason -> explicit_reason
    end
    |> sanitize_validation_reason_code()
  end

  defp resolve_validation_reason_code(_error, normalized_type) do
    sanitize_validation_reason_code(normalized_type)
  end

  defp sanitize_validation_reason_code(value) do
    case normalize_optional_string(value) do
      nil ->
        @validation_error_type

      reason_code ->
        reason_code
        |> String.downcase()
        |> String.replace(@validation_reason_code_pattern, "_")
    end
  end

  defp generic_validation_error_response do
    %{success: false, errors: [generic_validation_error()]}
  end

  defp generic_validation_error do
    %{
      type: @validation_error_type,
      short_message: @validation_error_default_short_message,
      message: @validation_error_default_message,
      vars: %{},
      fields: [],
      path: [],
      details: %{
        reason: @validation_redaction_failure_reason
      }
    }
  end

  defp log_validation_redaction_failure(reason) do
    Logger.warning("#{@rpc_validation_redaction_event} reason=#{validation_redaction_reason_type(reason)}")
  end

  defp validation_error_redactor do
    Application.get_env(:jido_code, :rpc_validation_error_redactor, LogRedactor)
  end

  defp validation_redaction_reason_type(%{error_type: error_type}) when is_binary(error_type),
    do: sanitize_validation_reason_code(error_type)

  defp validation_redaction_reason_type(%{"error_type" => error_type}) when is_binary(error_type),
    do: sanitize_validation_reason_code(error_type)

  defp validation_redaction_reason_type(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> sanitize_validation_reason_code()

  defp validation_redaction_reason_type(_reason), do: "unknown"

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
