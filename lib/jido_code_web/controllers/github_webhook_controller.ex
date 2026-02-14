defmodule JidoCodeWeb.GitHubWebhookController do
  use JidoCodeWeb, :controller

  require Logger

  alias JidoCode.GitHub.WebhookPipeline
  alias JidoCode.GitHub.WebhookSignature

  @signature_errors [
    :missing_webhook_secret,
    :missing_signature_header,
    :invalid_signature_header,
    :signature_mismatch
  ]

  def create(conn, params) do
    signature_header = req_header(conn, "x-hub-signature-256")
    delivery_id = req_header(conn, "x-github-delivery")
    event = req_header(conn, "x-github-event")
    raw_payload = Map.get(conn.assigns, :raw_body, "")

    with :ok <- WebhookSignature.verify(raw_payload, signature_header),
         :ok <-
           WebhookPipeline.route_verified_delivery(%{
             delivery_id: delivery_id,
             event: event,
             payload: params,
             raw_payload: raw_payload
           }) do
      Logger.info(
        "security_audit=github_webhook_signature_verified delivery_id=#{log_value(delivery_id)} event=#{log_value(event)}"
      )

      conn
      |> put_status(:accepted)
      |> json(%{status: "accepted"})
    else
      {:error, reason} when reason in @signature_errors ->
        Logger.warning(
          "security_audit=github_webhook_signature_rejected reason=#{reason} delivery_id=#{log_value(delivery_id)} event=#{log_value(event)}"
        )

        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid_signature"})

      {:error, reason} ->
        Logger.error(
          "github_webhook_delivery_failed reason=#{inspect(reason)} delivery_id=#{log_value(delivery_id)} event=#{log_value(event)}"
        )

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "delivery_processing_failed"})
    end
  end

  defp req_header(conn, header_name) when is_binary(header_name) do
    case Plug.Conn.get_req_header(conn, header_name) do
      [value | _rest] -> value
      _ -> nil
    end
  end

  defp log_value(value) when is_binary(value) and value != "", do: value
  defp log_value(_value), do: "unknown"
end
