defmodule AgentJido.GitHub do
  use Ash.Domain, otp_app: :agent_jido, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource AgentJido.GitHub.Repo
    resource AgentJido.GitHub.WebhookDelivery
    resource AgentJido.GitHub.IssueAnalysis
  end
end
