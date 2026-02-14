defmodule JidoCode.Forge.ClaudePromptRedactionTest do
  use ExUnit.Case, async: false

  alias JidoCode.Forge.Runners.ClaudeCode
  alias JidoCode.Security.LogRedactor

  defmodule CapturingClient do
    defstruct [:pid]

    def impl_module, do: __MODULE__

    def exec(%__MODULE__{pid: pid}, command, _opts) do
      send(pid, {:sprite_exec, command})

      output =
        Jason.encode!(%{
          "type" => "result",
          "subtype" => "success",
          "result" => "ok",
          "cost_usd" => 0.0,
          "duration_ms" => 1,
          "session_id" => "redaction-test"
        })

      {output <> "\n", 0}
    end

    def write_file(%__MODULE__{pid: pid}, path, content) do
      send(pid, {:sprite_write_file, path, content})
      :ok
    end
  end

  defmodule FailingRedactor do
    def redact_event(_value) do
      {:error, %{error_type: "forced_redaction_failure", message: "forced redaction failure for test"}}
    end

    def redact_string(_value) do
      {:error, %{error_type: "forced_redaction_failure", message: "forced redaction failure for test"}}
    end
  end

  setup do
    original_redactor = Application.get_env(:jido_code, :forge_prompt_redactor, LogRedactor)

    on_exit(fn ->
      Application.put_env(:jido_code, :forge_prompt_redactor, original_redactor)
    end)

    Application.put_env(:jido_code, :forge_prompt_redactor, LogRedactor)
    :ok
  end

  test "run_iteration masks prompt payload values before Claude invocation" do
    secret = "sk-test-0123456789abcdef"
    client = %CapturingClient{pid: self()}

    assert {:ok, %{status: :done}} =
             ClaudeCode.run_iteration(client, %{}, prompt: "Use token #{secret} to continue.")

    assert_receive {:sprite_exec, command}
    assert command =~ "[REDACTED"
    refute command =~ secret
  end

  test "init writes redacted prompt and context templates" do
    secret = "ghp_1234567890abcdef"
    client = %CapturingClient{pid: self()}

    assert :ok =
             ClaudeCode.init(client, %{
               prompt_template: "token=#{secret}",
               context_template: "Authorization: Bearer #{secret}"
             })

    assert_receive {:sprite_write_file, "/var/local/forge/templates/iterate.md", iterate_template}
    assert iterate_template =~ "[REDACTED"
    refute iterate_template =~ secret

    assert_receive {:sprite_write_file, "/var/local/forge/templates/context.md", context_template}
    assert context_template =~ "Authorization: Bearer [REDACTED"
    refute context_template =~ secret
  end

  test "run_iteration blocks LLM execution when prompt redaction fails" do
    secret = "sk-test-0123456789abcdef"
    client = %CapturingClient{pid: self()}

    Application.put_env(:jido_code, :forge_prompt_redactor, FailingRedactor)

    assert {:error, typed_error} =
             ClaudeCode.run_iteration(client, %{}, prompt: "Authorization: Bearer #{secret}")

    assert typed_error.error_type == "forge_prompt_redaction_failed"
    assert typed_error.operation == :run_iteration_prompt
    assert typed_error.reason_type == "forced_redaction_failure"
    refute_receive {:sprite_exec, _command}, 200
  end
end
