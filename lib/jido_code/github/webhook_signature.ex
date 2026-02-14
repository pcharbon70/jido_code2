defmodule JidoCode.GitHub.WebhookSignature do
  @moduledoc """
  Verifies `X-Hub-Signature-256` headers for inbound GitHub webhook deliveries.
  """

  @signature_prefix "sha256="
  @sha256_hex_length 64
  @sha256_hex_pattern ~r/\A[0-9a-fA-F]{64}\z/

  @type verify_error ::
          :missing_webhook_secret
          | :missing_signature_header
          | :invalid_signature_header
          | :signature_mismatch

  @spec verify(binary(), binary() | nil) :: :ok | {:error, verify_error()}
  def verify(payload, signature_header) when is_binary(payload) do
    with {:ok, secret} <- fetch_secret(),
         {:ok, provided_digest} <- parse_signature_header(signature_header),
         expected_digest <- sign_payload(payload, secret),
         true <- Plug.Crypto.secure_compare(expected_digest, provided_digest) do
      :ok
    else
      false ->
        {:error, :signature_mismatch}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def verify(_payload, _signature_header), do: {:error, :signature_mismatch}

  defp fetch_secret do
    case Application.get_env(:jido_code, :github_webhook_secret) do
      secret when is_binary(secret) ->
        trimmed_secret = String.trim(secret)

        if trimmed_secret == "" do
          {:error, :missing_webhook_secret}
        else
          {:ok, trimmed_secret}
        end

      _ ->
        {:error, :missing_webhook_secret}
    end
  end

  defp parse_signature_header(nil), do: {:error, :missing_signature_header}

  defp parse_signature_header(signature_header) when is_binary(signature_header) do
    normalized_header = String.trim(signature_header)

    case normalized_header do
      @signature_prefix <> digest when byte_size(digest) == @sha256_hex_length ->
        if digest =~ @sha256_hex_pattern do
          {:ok, String.downcase(digest)}
        else
          {:error, :invalid_signature_header}
        end

      _ ->
        {:error, :invalid_signature_header}
    end
  end

  defp parse_signature_header(_signature_header), do: {:error, :invalid_signature_header}

  defp sign_payload(payload, secret) when is_binary(payload) and is_binary(secret) do
    :crypto.mac(:hmac, :sha256, secret, payload)
    |> Base.encode16(case: :lower)
  end
end
