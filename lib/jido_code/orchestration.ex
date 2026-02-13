defmodule JidoCode.Orchestration do
  @moduledoc false
  use Ash.Domain, otp_app: :jido_code, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource JidoCode.Orchestration.WorkflowDefinition
    resource JidoCode.Orchestration.WorkflowRun
    resource JidoCode.Orchestration.Artifact
    resource JidoCode.Orchestration.PullRequest
  end
end
