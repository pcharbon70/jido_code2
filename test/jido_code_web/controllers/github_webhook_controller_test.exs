defmodule JidoCodeWeb.GitHubWebhookControllerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Phoenix.ConnTest
  import Plug.Conn

  require Logger

  @endpoint JidoCodeWeb.Endpoint

  @webhook_path "/api/github/webhooks"

  setup_all do
    case Process.whereis(JidoCodeWeb.Endpoint) do
      nil -> start_supervised!(JidoCodeWeb.Endpoint)
      _pid -> :ok
    end

    :ok
  end

  setup do
    original_log_level = Logger.level()
    Logger.configure(level: :info)

    original_secret = Application.get_env(:jido_code, :github_webhook_secret, :__missing__)

    original_dispatcher =
      Application.get_env(:jido_code, :github_webhook_verified_dispatcher, :__missing__)

    on_exit(fn ->
      Logger.configure(level: original_log_level)
      restore_env(:github_webhook_secret, original_secret)
      restore_env(:github_webhook_verified_dispatcher, original_dispatcher)
    end)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  test "accepts verified deliveries and forwards to idempotency/trigger mapping handoff", %{conn: conn} do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(test_pid, {:verified_delivery_handoff, delivery})
      :ok
    end)

    payload = Jason.encode!(%{"action" => "opened", "issue" => %{"number" => 42}})
    delivery_id = "delivery-#{System.unique_integer([:positive])}"
    event = "issues"

    log_output =
      capture_log([level: :info], fn ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", sign(payload, secret))
          |> put_req_header("x-github-delivery", delivery_id)
          |> put_req_header("x-github-event", event)
          |> post(@webhook_path, payload)
          |> json_response(202)

        assert response["status"] == "accepted"
      end)

    assert_receive {:verified_delivery_handoff, handoff}
    assert handoff.delivery_id == delivery_id
    assert handoff.event == event
    assert handoff.payload["action"] == "opened"
    assert handoff.raw_payload == payload

    assert log_output =~ "security_audit=github_webhook_signature_verified"
    assert log_output =~ "delivery_id=#{delivery_id}"
    assert log_output =~ "event=#{event}"
  end

  test "rejects delivery when signature verification fails and does not route side effects", %{conn: conn} do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(test_pid, {:verified_delivery_handoff, delivery})
      :ok
    end)

    payload = Jason.encode!(%{"action" => "opened", "issue" => %{"number" => 43}})
    delivery_id = "delivery-#{System.unique_integer([:positive])}"
    event = "issues"

    log_output =
      capture_log(fn ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", "sha256=deadbeef")
          |> put_req_header("x-github-delivery", delivery_id)
          |> put_req_header("x-github-event", event)
          |> post(@webhook_path, payload)
          |> json_response(401)

        assert response["error"] == "invalid_signature"
      end)

    refute_receive {:verified_delivery_handoff, _delivery}
    assert log_output =~ "security_audit=github_webhook_signature_rejected"
    assert log_output =~ "delivery_id=#{delivery_id}"
    assert log_output =~ "event=#{event}"
  end

  defp sign(payload, secret) do
    digest =
      :crypto.mac(:hmac, :sha256, secret, payload)
      |> Base.encode16(case: :lower)

    "sha256=#{digest}"
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)

  defp restore_env(key, value) do
    Application.put_env(:jido_code, key, value)
  end
end
