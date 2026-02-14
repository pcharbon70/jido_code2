defmodule JidoCode.GitHub.WebhookPipeline do
  @moduledoc """
  Routes verified webhook deliveries into downstream pipeline stages.
  """

  require Logger

  @type verified_delivery :: %{
          delivery_id: String.t() | nil,
          event: String.t() | nil,
          payload: map(),
          raw_payload: binary()
        }

  @spec route_verified_delivery(verified_delivery()) :: :ok | {:error, :verified_dispatch_failed}
  def route_verified_delivery(%{} = delivery) do
    dispatch_verified_delivery(delivery)
  end

  @doc false
  @spec default_dispatcher(verified_delivery()) :: :ok
  def default_dispatcher(%{} = delivery) do
    Logger.info(
      "github_webhook_pipeline_handoff stage=idempotency stage_next=trigger_mapping delivery_id=#{log_value(Map.get(delivery, :delivery_id))} event=#{log_value(Map.get(delivery, :event))}"
    )

    :ok
  end

  defp dispatch_verified_delivery(delivery) do
    dispatcher =
      Application.get_env(
        :jido_code,
        :github_webhook_verified_dispatcher,
        &__MODULE__.default_dispatcher/1
      )

    case safe_dispatch(dispatcher, delivery) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error(
          "github_webhook_pipeline_dispatch_failed reason=#{inspect(reason)} delivery_id=#{log_value(Map.get(delivery, :delivery_id))} event=#{log_value(Map.get(delivery, :event))}"
        )

        {:error, :verified_dispatch_failed}
    end
  end

  defp safe_dispatch(dispatcher, delivery) when is_function(dispatcher, 1) do
    try do
      case dispatcher.(delivery) do
        :ok -> :ok
        {:ok, _result} -> :ok
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_dispatch_result, other}}
      end
    rescue
      exception ->
        {:error, {:dispatch_exception, Exception.message(exception)}}
    catch
      kind, reason ->
        {:error, {:dispatch_throw, {kind, reason}}}
    end
  end

  defp safe_dispatch(_dispatcher, _delivery), do: {:error, :invalid_dispatcher}

  defp log_value(value) when is_binary(value) and value != "", do: value
  defp log_value(_value), do: "unknown"
end
