defmodule JidoCode.Folio do
  @moduledoc false
  use Ash.Domain

  resources do
    resource JidoCode.Folio.InboxItem
    resource JidoCode.Folio.Action
    resource JidoCode.Folio.Project
  end
end
