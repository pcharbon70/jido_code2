defmodule JidoCodeWeb.Security.UiRedactionTest do
  use ExUnit.Case, async: false

  alias JidoCode.Security.LogRedactor
  alias JidoCodeWeb.Security.UiRedaction

  defmodule FailingRedactor do
    def redact_string(_value) do
      {:error, %{error_type: "forced_redaction_failure", message: "forced redaction failure for test"}}
    end
  end

  setup do
    original_redactor = Application.get_env(:jido_code, :forge_ui_redactor, LogRedactor)

    on_exit(fn ->
      Application.put_env(:jido_code, :forge_ui_redactor, original_redactor)
    end)

    Application.put_env(:jido_code, :forge_ui_redactor, LogRedactor)
    :ok
  end

  test "masks known secret patterns with placeholder text" do
    secret = "sk-test-0123456789abcdef"
    result = UiRedaction.sanitize_text("Authorization: Bearer #{secret}")

    assert result.text =~ "Authorization: Bearer [REDACTED"
    refute result.text =~ secret
    assert result.redacted?
    refute result.security_alert?
    refute result.suppressed?
  end

  test "suppresses unsafe values detected after redaction and raises alert" do
    leaked_token = "xoxb-12345678901234567890"
    result = UiRedaction.sanitize_text("leaked slack credential #{leaked_token}")

    assert result.text == "[SENSITIVE CONTENT SUPPRESSED]"
    assert result.security_alert?
    assert result.suppressed?
    assert result.reason == :post_render_sensitive
  end

  test "suppresses content when ui redactor fails" do
    Application.put_env(:jido_code, :forge_ui_redactor, FailingRedactor)

    result = UiRedaction.sanitize_text("Authorization: Bearer sk-test-0123456789abcdef")

    assert result.text == "[SENSITIVE CONTENT SUPPRESSED]"
    assert result.security_alert?
    assert result.suppressed?
    assert result.reason == :redaction_failed
  end
end
