defmodule JidoCode.TestSupport.FailingRpcValidationErrorRedactor do
  @moduledoc false

  def redact_event(_payload) do
    {:error, %{error_type: "forced_redaction_failure", message: "forced redaction failure for test"}}
  end
end
