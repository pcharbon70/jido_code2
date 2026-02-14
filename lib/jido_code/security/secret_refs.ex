defmodule JidoCode.Security.SecretRefs do
  @moduledoc """
  SecretRef persistence and metadata reads for `/settings/security`.
  """

  alias JidoCode.Security.{Encryption, SecretRef}

  @encryption_unavailable_recovery_instruction """
  Set `JIDO_CODE_SECRET_REF_ENCRYPTION_KEY` to a base64-encoded 32-byte key and restart JidoCode.
  """

  @write_failed_recovery_instruction """
  Retry the save. If it still fails, inspect database connectivity and rerun containment steps from the security playbook.
  """

  @read_failed_recovery_instruction """
  Refresh this page. If metadata loading still fails, verify database health before retrying.
  """

  @typedoc """
  Typed secret persistence/read error payload with remediation guidance.
  """
  @type typed_error :: %{
          error_type: String.t(),
          message: String.t(),
          recovery_instruction: String.t()
        }

  @typedoc """
  Non-sensitive SecretRef fields safe for settings displays.
  """
  @type secret_metadata :: %{
          id: Ecto.UUID.t(),
          scope: :instance | :project | :integration,
          name: String.t(),
          key_version: integer(),
          source: :env | :onboarding | :rotation,
          last_rotated_at: DateTime.t(),
          expires_at: DateTime.t() | nil
        }

  @doc """
  Persists an operational secret as an encrypted `SecretRef`.
  """
  @spec persist_operational_secret(map()) :: {:ok, secret_metadata()} | {:error, typed_error()}
  def persist_operational_secret(params) when is_map(params) do
    with {:ok, scope} <- normalize_scope(Map.get(params, :scope) || Map.get(params, "scope")),
         {:ok, name} <- normalize_name(Map.get(params, :name) || Map.get(params, "name")),
         {:ok, value} <- normalize_value(Map.get(params, :value) || Map.get(params, "value")),
         {:ok, source} <- normalize_source(Map.get(params, :source) || Map.get(params, "source")),
         {:ok, encrypted_ciphertext} <- Encryption.encrypt(value),
         {:ok, secret_ref} <- create_secret_ref(scope, name, encrypted_ciphertext, source) do
      {:ok, to_metadata(secret_ref)}
    else
      {:error, :invalid_scope} ->
        {:error,
         typed_error(
           "secret_scope_invalid",
           "Secret scope must be one of instance, project, or integration.",
           @write_failed_recovery_instruction
         )}

      {:error, :invalid_name} ->
        {:error,
         typed_error(
           "secret_name_invalid",
           "Secret name must be a non-empty string.",
           @write_failed_recovery_instruction
         )}

      {:error, :invalid_value} ->
        {:error,
         typed_error(
           "secret_value_invalid",
           "Secret value must be a non-empty string.",
           @write_failed_recovery_instruction
         )}

      {:error, :invalid_source} ->
        {:error,
         typed_error(
           "secret_source_invalid",
           "Secret source must be env, onboarding, or rotation.",
           @write_failed_recovery_instruction
         )}

      {:error, :encryption_config_unavailable} ->
        {:error,
         typed_error(
           "secret_encryption_unavailable",
           "Secret encryption is unavailable and no secret was persisted.",
           @encryption_unavailable_recovery_instruction
         )}

      {:error, :encryption_failed} ->
        {:error,
         typed_error(
           "secret_encryption_failed",
           "Secret encryption failed and no secret was persisted.",
           @write_failed_recovery_instruction
         )}

      {:error, _reason} ->
        {:error,
         typed_error(
           "secret_persistence_failed",
           "Secret persistence failed and no secret was persisted.",
           @write_failed_recovery_instruction
         )}
    end
  end

  def persist_operational_secret(_params) do
    {:error,
     typed_error(
       "secret_persistence_failed",
       "Secret persistence failed and no secret was persisted.",
       @write_failed_recovery_instruction
     )}
  end

  @doc """
  Reads non-sensitive SecretRef metadata for `/settings/security`.
  """
  @spec list_secret_metadata() :: {:ok, [secret_metadata()]} | {:error, typed_error()}
  def list_secret_metadata do
    case SecretRef.list_metadata(authorize?: false) do
      {:ok, records} ->
        {:ok, Enum.map(records, &to_metadata/1)}

      {:error, _reason} ->
        {:error,
         typed_error(
           "secret_metadata_unavailable",
           "Secret metadata could not be loaded.",
           @read_failed_recovery_instruction
         )}
    end
  end

  defp create_secret_ref(scope, name, encrypted_ciphertext, source) do
    SecretRef.create(
      %{
        scope: scope,
        name: name,
        ciphertext: encrypted_ciphertext,
        source: source,
        key_version: 1,
        last_rotated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      },
      authorize?: false
    )
  end

  defp normalize_scope(scope) when scope in [:instance, :project, :integration], do: {:ok, scope}
  defp normalize_scope("instance"), do: {:ok, :instance}
  defp normalize_scope("project"), do: {:ok, :project}
  defp normalize_scope("integration"), do: {:ok, :integration}
  defp normalize_scope(_scope), do: {:error, :invalid_scope}

  defp normalize_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> {:error, :invalid_name}
      normalized_name -> {:ok, normalized_name}
    end
  end

  defp normalize_name(_name), do: {:error, :invalid_name}

  defp normalize_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, :invalid_value}
      _normalized_value -> {:ok, value}
    end
  end

  defp normalize_value(_value), do: {:error, :invalid_value}

  defp normalize_source(nil), do: {:ok, :onboarding}
  defp normalize_source(source) when source in [:env, :onboarding, :rotation], do: {:ok, source}
  defp normalize_source("env"), do: {:ok, :env}
  defp normalize_source("onboarding"), do: {:ok, :onboarding}
  defp normalize_source("rotation"), do: {:ok, :rotation}
  defp normalize_source(_source), do: {:error, :invalid_source}

  defp typed_error(error_type, message, recovery_instruction) do
    %{
      error_type: error_type,
      message: message,
      recovery_instruction: recovery_instruction
    }
  end

  defp to_metadata(%SecretRef{} = secret_ref) do
    %{
      id: secret_ref.id,
      scope: secret_ref.scope,
      name: secret_ref.name,
      key_version: secret_ref.key_version,
      source: secret_ref.source,
      last_rotated_at: secret_ref.last_rotated_at,
      expires_at: secret_ref.expires_at
    }
  end
end
