defmodule AgentJido.Forge.Manager do
  @moduledoc """
  Session lifecycle management for Forge.

  Tracks active sessions, starts them under DynamicSupervisor,
  and registers them in Registry.
  """

  use GenServer

  require Logger

  alias AgentJido.Forge.PubSub, as: ForgePubSub
  alias AgentJido.Forge.SpriteSession

  @supervisor AgentJido.Forge.SpriteSupervisor
  @registry AgentJido.Forge.SessionRegistry

  # Public API

  @doc """
  Starts the manager.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Starts a new session.
  """
  @spec start_session(String.t(), map()) :: {:ok, pid()} | {:error, term()}
  def start_session(session_id, spec) do
    GenServer.call(__MODULE__, {:start_session, session_id, spec})
  end

  @doc """
  Stops a session.
  """
  @spec stop_session(String.t(), term()) :: :ok | {:error, term()}
  def stop_session(session_id, reason \\ :normal) do
    GenServer.call(__MODULE__, {:stop_session, session_id, reason})
  end

  @doc """
  Lists all active session IDs.
  """
  @spec list_sessions() :: [String.t()]
  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  @doc """
  Gets the pid of a session.
  """
  @spec get_session(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def get_session(session_id) do
    case Registry.lookup(@registry, session_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{sessions: MapSet.new()}}
  end

  @impl true
  def handle_call({:start_session, session_id, spec}, _from, state) do
    case Registry.lookup(@registry, session_id) do
      [{pid, _}] ->
        {:reply, {:error, {:already_started, pid}}, state}

      [] ->
        child_spec = {SpriteSession, {session_id, spec, []}}

        case DynamicSupervisor.start_child(@supervisor, child_spec) do
          {:ok, pid} ->
            Process.monitor(pid)
            new_sessions = MapSet.put(state.sessions, session_id)
            Logger.debug("Started session #{session_id} with pid #{inspect(pid)}")
            ForgePubSub.broadcast_sessions({:session_started, session_id})
            {:reply, {:ok, pid}, %{state | sessions: new_sessions}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:stop_session, session_id, reason}, _from, state) do
    case Registry.lookup(@registry, session_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(@supervisor, pid)
        new_sessions = MapSet.delete(state.sessions, session_id)
        Logger.debug("Stopped session #{session_id}")
        ForgePubSub.broadcast_sessions({:session_stopped, session_id, reason})
        {:reply, :ok, %{state | sessions: new_sessions}}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:list_sessions, _from, state) do
    session_list = MapSet.to_list(state.sessions)
    {:reply, session_list, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    active_sessions =
      state.sessions
      |> MapSet.to_list()
      |> Enum.filter(fn session_id ->
        case Registry.lookup(@registry, session_id) do
          [{_pid, _}] -> true
          [] -> false
        end
      end)
      |> MapSet.new()

    {:noreply, %{state | sessions: active_sessions}}
  end
end
