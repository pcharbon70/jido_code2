defmodule JidoCode.Forge.PersistenceRedactionTest do
  use JidoCode.DataCase, async: false

  alias JidoCode.Forge.Persistence
  alias JidoCode.Forge.Resources.Session
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
    original_persistence_config = Application.get_env(:jido_code, JidoCode.Forge.Persistence)

    on_exit(fn ->
      Application.put_env(:jido_code, :forge_channel_redactor, original_redactor)

      if original_persistence_config do
        Application.put_env(:jido_code, JidoCode.Forge.Persistence, original_persistence_config)
      else
        Application.delete_env(:jido_code, JidoCode.Forge.Persistence)
      end
    end)

    Application.put_env(:jido_code, :forge_channel_redactor, LogRedactor)
    Application.put_env(:jido_code, JidoCode.Forge.Persistence, enabled: true)
    :ok
  end

  test "record_execution_complete persists masked artifact data only" do
    session_id = "persist-redaction-#{System.unique_integer([:positive])}"
    secret = "sk-test-0123456789abcdef"
    session = create_session!(session_id)

    assert {:ok, _updated_session} =
             Persistence.record_execution_complete(session_id, %{
               status: :done,
               output: "Authorization: Bearer #{secret}",
               runner_state: %{api_token: secret}
             })

    reloaded = Ash.get!(Session, session.id)

    assert is_binary(reloaded.output_buffer)
    assert reloaded.output_buffer =~ "Authorization: Bearer [REDACTED"
    refute reloaded.output_buffer =~ secret

    redacted_api_token =
      Map.get(reloaded.runner_state, :api_token) || Map.get(reloaded.runner_state, "api_token")

    assert is_binary(redacted_api_token)
    assert redacted_api_token =~ "len="
    refute redacted_api_token == secret
  end

  test "record_execution_complete blocks persistence with typed security error when redaction fails" do
    Application.put_env(:jido_code, :forge_channel_redactor, FailingRedactor)

    session_id = "persist-redaction-failure-#{System.unique_integer([:positive])}"
    session = create_session!(session_id)

    assert {:error, typed_error} =
             Persistence.record_execution_complete(session_id, %{
               status: :done,
               output: "Authorization: Bearer sk-test-0123456789abcdef"
             })

    assert typed_error.error_type == "forge_channel_redaction_failed"
    assert typed_error.channel == :artifact
    assert typed_error.operation == :record_execution_complete
    assert typed_error.reason_type == "forced_redaction_failure"

    reloaded = Ash.get!(Session, session.id)
    assert reloaded.phase == :created
    assert is_nil(reloaded.output_buffer)
  end

  defp create_session!(session_id) do
    Session
    |> Ash.Changeset.for_create(:create, %{
      name: session_id,
      spec: %{}
    })
    |> Ash.create!()
  end
end
