defmodule JidoCode.Forge.Domain do
  @moduledoc false
  use Ash.Domain, otp_app: :jido_code, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource JidoCode.Forge.Resources.SpriteSpec
    resource JidoCode.Forge.Resources.Workflow
    resource JidoCode.Forge.Resources.Session
    resource JidoCode.Forge.Resources.Checkpoint
    resource JidoCode.Forge.Resources.ExecSession
    resource JidoCode.Forge.Resources.Event
  end
end
