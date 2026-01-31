defmodule AgentJido.Forge do
  @moduledoc """
  Jido Forge - Generic parallel sandbox execution.

  Forge manages sprite sessions with pluggable runners.
  """

  alias AgentJido.Forge.{Manager, SpriteSession}

  # Session management

  @doc """
  Starts a new forge session.
  """
  @spec start_session(String.t(), map()) :: {:ok, pid()} | {:error, term()}
  def start_session(session_id, spec) do
    Manager.start_session(session_id, spec)
  end

  @doc """
  Stops a session.
  """
  @spec stop_session(String.t(), term()) :: :ok | {:error, term()}
  def stop_session(session_id, reason \\ :normal) do
    Manager.stop_session(session_id, reason)
  end

  @doc """
  Lists all active session IDs.
  """
  @spec list_sessions() :: [String.t()]
  def list_sessions do
    Manager.list_sessions()
  end

  @doc """
  Gets the current status of a session.
  """
  @spec status(String.t()) :: {:ok, map()} | {:error, term()}
  def status(session_id) do
    SpriteSession.status(session_id)
  end

  # Execution

  @doc """
  Runs a single iteration on the session.
  """
  @spec run_iteration(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_iteration(session_id, opts \\ []) do
    SpriteSession.run_iteration(session_id, opts)
  end

  @doc """
  Executes a command directly in the sprite.
  """
  @spec exec(String.t(), String.t(), keyword()) ::
          {String.t(), non_neg_integer()} | {:error, term()}
  def exec(session_id, command, opts \\ []) do
    SpriteSession.exec(session_id, command, opts)
  end

  @doc """
  Applies input when session is in :needs_input state.
  """
  @spec apply_input(String.t(), term()) :: :ok | {:error, term()}
  def apply_input(session_id, input) do
    SpriteSession.apply_input(session_id, input)
  end

  @doc """
  Runs iterations in a loop until done, blocked, needs_input, or error.

  ## Options

    * `:max_iterations` - Maximum number of iterations (default: 50)

  Returns the final iteration result.
  """
  @spec run_loop(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_loop(session_id, opts \\ []) do
    max_iterations = Keyword.get(opts, :max_iterations, 50)
    do_run_loop(session_id, opts, max_iterations, 0)
  end

  defp do_run_loop(_session_id, _opts, max_iterations, iteration)
       when iteration >= max_iterations do
    {:error, :max_iterations_reached}
  end

  defp do_run_loop(session_id, opts, max_iterations, iteration) do
    case run_iteration(session_id, opts) do
      {:ok, %{status: :done} = result} ->
        {:ok, result}

      {:ok, %{status: :needs_input} = result} ->
        {:ok, result}

      {:ok, %{status: :blocked} = result} ->
        {:ok, result}

      {:ok, %{status: :error} = result} ->
        {:ok, result}

      {:ok, %{continue: true} = _result} ->
        do_run_loop(session_id, opts, max_iterations, iteration + 1)

      {:ok, %{status: :continue} = _result} ->
        do_run_loop(session_id, opts, max_iterations, iteration + 1)

      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
