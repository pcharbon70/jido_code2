defmodule JidoCode.GitHub do
  use Ash.Domain, otp_app: :jido_code, extensions: [AshAdmin.Domain, AshTypescript.Rpc]

  admin do
    show? true
  end

  typescript_rpc do
    resource JidoCode.GitHub.Repo do
      rpc_action :rpc_list_repositories, :read
      rpc_action :rpc_list_repositories_session_or_bearer, :read
    end
  end

  resources do
    resource JidoCode.GitHub.Repo
    resource JidoCode.GitHub.WebhookDelivery
    resource JidoCode.GitHub.IssueAnalysis
  end
end
