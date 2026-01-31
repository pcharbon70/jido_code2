defmodule AgentJido.Forge.SpriteClient do
  @moduledoc """
  Facade for sprite client operations.

  Delegates all calls to the configured implementation module.
  Configure via:

      config :agent_jido, :forge_sprite_client, MyApp.SpriteClient.Impl

  Defaults to `AgentJido.Forge.SpriteClient.Fake` for development and testing.
  """

  @behaviour AgentJido.Forge.SpriteClient.Behaviour

  defp impl do
    Application.get_env(:agent_jido, :forge_sprite_client, AgentJido.Forge.SpriteClient.Fake)
  end

  @impl true
  def create(spec) do
    impl().create(spec)
  end

  @impl true
  def exec(client, command, opts \\ []) do
    impl().exec(client, command, opts)
  end

  @impl true
  def spawn(client, command, args, opts \\ []) do
    impl().spawn(client, command, args, opts)
  end

  @impl true
  def write_file(client, path, content) do
    impl().write_file(client, path, content)
  end

  @impl true
  def read_file(client, path) do
    impl().read_file(client, path)
  end

  @impl true
  def inject_env(client, env_map) do
    impl().inject_env(client, env_map)
  end

  @impl true
  def destroy(client, sprite_id) do
    impl().destroy(client, sprite_id)
  end
end
