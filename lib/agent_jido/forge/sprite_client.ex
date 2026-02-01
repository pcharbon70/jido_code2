defmodule AgentJido.Forge.SpriteClient do
  @moduledoc """
  Facade for sprite client operations.

  Delegates all calls to the appropriate implementation module based on
  the client struct type. For `create/1`, uses the configured implementation.

  Configure via:

      config :agent_jido, :forge_sprite_client, MyApp.SpriteClient.Impl

  Defaults to `AgentJido.Forge.SpriteClient.Fake` for development and testing.
  """

  @behaviour AgentJido.Forge.SpriteClient.Behaviour

  alias AgentJido.Forge.SpriteClient.{Fake, Live}

  defp impl do
    Application.get_env(:agent_jido, :forge_sprite_client, Fake)
  end

  defp impl_for(%Fake{}), do: Fake
  defp impl_for(%Live{}), do: Live

  @impl true
  def create(spec) do
    impl().create(spec)
  end

  @impl true
  def exec(client, command, opts \\ []) do
    impl_for(client).exec(client, command, opts)
  end

  @impl true
  def spawn(client, command, args, opts \\ []) do
    impl_for(client).spawn(client, command, args, opts)
  end

  @impl true
  def write_file(client, path, content) do
    impl_for(client).write_file(client, path, content)
  end

  @impl true
  def read_file(client, path) do
    impl_for(client).read_file(client, path)
  end

  @impl true
  def inject_env(client, env_map) do
    impl_for(client).inject_env(client, env_map)
  end

  @impl true
  def destroy(client, sprite_id) do
    impl_for(client).destroy(client, sprite_id)
  end
end
