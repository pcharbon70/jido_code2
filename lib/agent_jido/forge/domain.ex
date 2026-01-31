defmodule AgentJido.Forge.Domain do
  use Ash.Domain, otp_app: :agent_jido, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource AgentJido.Forge.Resources.SpriteSpec
    resource AgentJido.Forge.Resources.Workflow
    resource AgentJido.Forge.Resources.Session
  end
end
