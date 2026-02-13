defmodule JidoCode.Setup.RuntimeMode do
  @moduledoc """
  Resolves the effective runtime mode used by onboarding and auth controls.
  """

  @production_modes [:prod, :production, "prod", "production"]

  @spec current() :: atom() | String.t()
  def current do
    Application.get_env(:jido_code, :runtime_mode, :dev)
  end

  @spec production?() :: boolean()
  def production? do
    current() in @production_modes
  end
end
