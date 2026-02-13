defmodule JidoCode.Projects do
  @moduledoc false
  use Ash.Domain, otp_app: :jido_code, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource JidoCode.Projects.Project
    resource JidoCode.Projects.ProjectSecret
  end
end
