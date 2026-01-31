defmodule AgentJido.Forge.Runners.Custom do
  @moduledoc """
  Allows passing a custom module or function as the runner.
  """

  @behaviour AgentJido.Forge.Runner

  @impl true
  def init(client, %{init_fn: init_fn} = config) when is_function(init_fn, 2) do
    init_fn.(client, config)
  end

  def init(_client, _config), do: :ok

  @impl true
  def run_iteration(client, state, opts) do
    run_fn = opts[:run_fn] || state[:run_fn]

    if is_function(run_fn, 3) do
      run_fn.(client, state, opts)
    else
      {:error, :no_run_function}
    end
  end

  @impl true
  def apply_input(client, input, %{input_fn: input_fn} = state) when is_function(input_fn, 3) do
    input_fn.(client, input, state)
  end

  def apply_input(_client, _input, _state), do: {:error, :not_supported}
end
