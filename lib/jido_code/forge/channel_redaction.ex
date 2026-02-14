defmodule JidoCode.Forge.ChannelRedaction do
  @moduledoc """
  Redaction gate for Forge PubSub and artifact channels.
  """

  alias JidoCode.Security.LogRedactor

  @typedoc """
  Typed security error returned when channel redaction fails.
  """
  @type typed_security_error :: %{
          error_type: String.t(),
          channel: :pubsub | :artifact,
          operation: atom(),
          reason_type: String.t(),
          message: String.t()
        }

  @spec redact_pubsub_payload(term(), keyword()) :: {:ok, term()} | {:error, typed_security_error()}
  def redact_pubsub_payload(payload, opts \\ []) do
    operation = Keyword.get(opts, :operation, :publish)
    redact_payload(payload, :pubsub, operation)
  end

  @spec redact_artifact_payload(term(), keyword()) :: {:ok, term()} | {:error, typed_security_error()}
  def redact_artifact_payload(payload, opts \\ []) do
    operation = Keyword.get(opts, :operation, :persist)
    redact_payload(payload, :artifact, operation)
  end

  defp redact_payload(payload, channel, operation) do
    case redact_term(payload) do
      {:ok, redacted_payload} ->
        {:ok, redacted_payload}

      {:error, reason} ->
        {:error, typed_error(channel, operation, reason)}
    end
  end

  defp redact_term(value) when is_map(value) do
    with_redactor_call(:redact_event, [value], fn
      {:ok, redacted_map} when is_map(redacted_map) ->
        {:ok, redacted_map}

      {:error, reason} ->
        {:error, reason}

      _other ->
        {:error, %{error_type: "redaction_invalid_response", message: "Unexpected redactor response."}}
    end)
  end

  defp redact_term(value) when is_binary(value) do
    with_redactor_call(:redact_string, [value], fn
      {:ok, redacted_string} when is_binary(redacted_string) ->
        {:ok, redacted_string}

      {:error, reason} ->
        {:error, reason}

      _other ->
        {:error, %{error_type: "redaction_invalid_response", message: "Unexpected redactor response."}}
    end)
  end

  defp redact_term(value) when is_list(value) do
    value
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case redact_term(item) do
        {:ok, redacted_item} ->
          {:cont, {:ok, [redacted_item | acc]}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, redacted_items} -> {:ok, Enum.reverse(redacted_items)}
      {:error, _reason} = error -> error
    end
  end

  defp redact_term(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> redact_term()
    |> case do
      {:ok, redacted_items} -> {:ok, List.to_tuple(redacted_items)}
      {:error, _reason} = error -> error
    end
  end

  defp redact_term(value), do: {:ok, value}

  defp with_redactor_call(function_name, args, response_handler) do
    redactor = redactor_module()

    try do
      redactor
      |> apply(function_name, args)
      |> response_handler.()
    rescue
      exception ->
        {:error, %{error_type: "redaction_exception", message: Exception.message(exception)}}
    catch
      kind, _reason ->
        {:error, %{error_type: "redaction_#{kind}", message: "Redaction crashed unexpectedly."}}
    end
  end

  defp redactor_module do
    Application.get_env(:jido_code, :forge_channel_redactor, LogRedactor)
  end

  defp typed_error(channel, operation, reason) do
    %{
      error_type: "forge_channel_redaction_failed",
      channel: channel,
      operation: operation,
      reason_type: reason_type(reason),
      message: "Channel redaction failed and publish/persistence was blocked."
    }
  end

  defp reason_type(%{error_type: error_type}) when is_binary(error_type), do: sanitize_reason_type(error_type)
  defp reason_type(%{"error_type" => error_type}) when is_binary(error_type), do: sanitize_reason_type(error_type)
  defp reason_type(reason) when is_atom(reason), do: reason |> Atom.to_string() |> sanitize_reason_type()
  defp reason_type(_reason), do: "unknown"

  defp sanitize_reason_type(type) do
    String.replace(type, ~r/[^a-zA-Z0-9._-]/, "_")
  end
end
