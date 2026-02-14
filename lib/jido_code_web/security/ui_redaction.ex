defmodule JidoCodeWeb.Security.UiRedaction do
  @moduledoc """
  Redaction and suppression helpers for LiveView rendering.
  """

  alias JidoCode.Security.LogRedactor

  @assignment_secret_pattern ~r/\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|token|secret|password|credential|passwd)\s*[:=]\s*(?!\[REDACTED)[^,\s;]+/iu
  @bearer_token_pattern ~r/\bBearer\s+(?!\[REDACTED)[A-Za-z0-9\-\._~\+\/=]{8,}\b/u
  @openai_token_pattern ~r/\bsk-[A-Za-z0-9\-_]{12,}\b/u
  @github_token_pattern ~r/\bgh[pousr]_[A-Za-z0-9]{12,}\b/u
  @github_pat_pattern ~r/\bgithub_pat_[A-Za-z0-9_]{12,}\b/u
  @jwt_pattern ~r/\b[A-Za-z0-9\-_]{16,}\.[A-Za-z0-9\-_]{16,}\.[A-Za-z0-9\-_]{16,}\b/u
  @slack_token_pattern ~r/\bxox[baprs]-[A-Za-z0-9-]{10,}\b/u

  @post_render_patterns [
    @assignment_secret_pattern,
    @bearer_token_pattern,
    @openai_token_pattern,
    @github_token_pattern,
    @github_pat_pattern,
    @jwt_pattern,
    @slack_token_pattern
  ]

  @typedoc """
  Sanitization output for UI rendering.
  """
  @type sanitization_result :: %{
          text: String.t(),
          redacted?: boolean(),
          suppressed?: boolean(),
          security_alert?: boolean(),
          reason: :clean | :redacted | :post_render_sensitive | :redaction_failed | :redaction_invalid_response
        }

  @spec sanitize_text(term(), keyword()) :: sanitization_result()
  def sanitize_text(value, opts \\ [])

  def sanitize_text(value, opts) when is_binary(value) do
    placeholder = Keyword.get(opts, :placeholder, "[SENSITIVE CONTENT SUPPRESSED]")

    case redact_string(value) do
      {:ok, redacted_value} when is_binary(redacted_value) ->
        cond do
          post_render_sensitive?(redacted_value) ->
            suppressed_result(placeholder, :post_render_sensitive, redacted_value != value)

          redacted_value != value ->
            %{
              text: redacted_value,
              redacted?: true,
              suppressed?: false,
              security_alert?: false,
              reason: :redacted
            }

          true ->
            %{
              text: value,
              redacted?: false,
              suppressed?: false,
              security_alert?: false,
              reason: :clean
            }
        end

      {:error, _reason} ->
        suppressed_result(placeholder, :redaction_failed, false)

      _other ->
        suppressed_result(placeholder, :redaction_invalid_response, false)
    end
  end

  def sanitize_text(value, opts) do
    value
    |> inspect(limit: 25, printable_limit: 2_500)
    |> sanitize_text(opts)
  end

  @spec security_alert_message(atom()) :: String.t()
  def security_alert_message(:post_render_sensitive) do
    "Security alert: Sensitive content was detected after redaction and suppressed."
  end

  def security_alert_message(:redaction_failed) do
    "Security alert: Content redaction failed and output was suppressed."
  end

  def security_alert_message(:redaction_invalid_response) do
    "Security alert: Content redaction returned an invalid response and output was suppressed."
  end

  def security_alert_message(_reason) do
    "Security alert: Sensitive content was suppressed."
  end

  defp redact_string(value) do
    redactor = redactor_module()

    try do
      redactor.redact_string(value)
    rescue
      exception ->
        {:error, %{error_type: "redaction_exception", message: Exception.message(exception)}}
    catch
      kind, _reason ->
        {:error, %{error_type: "redaction_#{kind}", message: "Redaction crashed unexpectedly."}}
    end
  end

  defp redactor_module do
    Application.get_env(:jido_code, :forge_ui_redactor, LogRedactor)
  end

  defp post_render_sensitive?(value) do
    Enum.any?(@post_render_patterns, &Regex.match?(&1, value))
  end

  defp suppressed_result(placeholder, reason, redacted?) do
    %{
      text: placeholder,
      redacted?: redacted?,
      suppressed?: true,
      security_alert?: true,
      reason: reason
    }
  end
end
