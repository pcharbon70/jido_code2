defmodule JidoCode.Forge.PubSubRedactionTest do
  use ExUnit.Case, async: false

  alias JidoCode.Forge.PubSub, as: ForgePubSub
  alias JidoCode.Security.LogRedactor

  defmodule FailingRedactor do
    def redact_event(_data) do
      {:error, %{error_type: "forced_redaction_failure", message: "forced redaction failure for test"}}
    end

    def redact_string(_value) do
      {:error, %{error_type: "forced_redaction_failure", message: "forced redaction failure for test"}}
    end
  end

  setup do
    original_redactor = Application.get_env(:jido_code, :forge_channel_redactor, LogRedactor)

    on_exit(fn ->
      Application.put_env(:jido_code, :forge_channel_redactor, original_redactor)
    end)

    Application.put_env(:jido_code, :forge_channel_redactor, LogRedactor)
    :ok
  end

  test "broadcast_session publishes masked payloads while preserving event order and shape" do
    session_id = "pubsub-redaction-#{System.unique_integer([:positive])}"
    secret_a = "sk-test-0123456789abcdef"
    secret_b = "ghp_1234567890abcdef"

    assert :ok = ForgePubSub.subscribe_session(session_id)

    assert :ok =
             ForgePubSub.broadcast_session(
               session_id,
               {:output, %{chunk: "Authorization: Bearer #{secret_a}", seq: 1}}
             )

    assert :ok =
             ForgePubSub.broadcast_session(
               session_id,
               {:output, %{chunk: "token=#{secret_b}", seq: 2}}
             )

    assert_receive {:output, %{chunk: first_chunk, seq: 1}}
    assert_receive {:output, %{chunk: second_chunk, seq: 2}}

    assert first_chunk =~ "Authorization: Bearer [REDACTED"
    assert second_chunk =~ "token=[REDACTED"
    refute first_chunk =~ secret_a
    refute second_chunk =~ secret_b
  end

  test "broadcast_session blocks publication and returns typed security error when redaction fails" do
    Application.put_env(:jido_code, :forge_channel_redactor, FailingRedactor)

    session_id = "pubsub-redaction-failure-#{System.unique_integer([:positive])}"
    secret = "sk-test-0123456789abcdef"

    assert :ok = ForgePubSub.subscribe_session(session_id)

    assert {:error, typed_error} =
             ForgePubSub.broadcast_session(
               session_id,
               {:output, %{chunk: "Authorization: Bearer #{secret}", seq: 1}}
             )

    assert typed_error.error_type == "forge_channel_redaction_failed"
    assert typed_error.channel == :pubsub
    assert typed_error.operation == :broadcast_session
    assert typed_error.reason_type == "forced_redaction_failure"
    refute_receive {:output, _payload}, 200
  end
end
