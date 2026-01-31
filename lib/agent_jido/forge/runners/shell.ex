defmodule AgentJido.Forge.Runners.Shell do
  @moduledoc """
  Simple shell command runner.

  Executes a shell command and returns the result. The command can be
  provided via opts or state.
  """

  @behaviour AgentJido.Forge.Runner

  alias AgentJido.Forge.SpriteClient

  @impl true
  def init(_client, _config) do
    :ok
  end

  @impl true
  def run_iteration(client, state, opts) do
    command = opts[:command] || state[:command]

    case SpriteClient.exec(client, command, opts) do
      {output, 0} ->
        {:ok,
         %{
           status: :done,
           output: output,
           summary: nil,
           question: nil,
           error: nil,
           metadata: %{exit_code: 0}
         }}

      {output, code} ->
        {:ok,
         %{
           status: :error,
           output: output,
           summary: nil,
           question: nil,
           error: "Exit code: #{code}",
           metadata: %{exit_code: code}
         }}
    end
  end

  @impl true
  def apply_input(_client, _input, _state) do
    {:error, :not_supported}
  end
end
