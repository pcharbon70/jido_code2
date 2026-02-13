defmodule JidoCode.Agents do
  @moduledoc false
  use Ash.Domain, otp_app: :jido_code, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource JidoCode.Agents.SupportAgentConfig
  end
end
