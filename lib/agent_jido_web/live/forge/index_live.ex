defmodule AgentJidoWeb.Forge.IndexLive do
  use AgentJidoWeb, :live_view

  alias AgentJido.Forge
  alias AgentJido.Forge.PubSub, as: ForgePubSub

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      ForgePubSub.subscribe_sessions()
    end

    sessions = load_sessions_with_status()

    {:ok,
     socket
     |> assign(:page_title, "Forge Sessions")
     |> assign(:sessions, sessions)}
  end

  @impl true
  def handle_info({:session_started, id}, socket) do
    case Forge.status(id) do
      {:ok, status} ->
        {:noreply, update(socket, :sessions, &[status | &1])}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:session_stopped, id, _reason}, socket) do
    {:noreply,
     update(socket, :sessions, fn sessions ->
       Enum.reject(sessions, &(&1.session_id == id))
     end)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("start_test_session", _, socket) do
    session_id = "test-#{:erlang.unique_integer([:positive])}"

    spec = %{
      runner: :shell,
      runner_config: %{},
      env: %{"TEST_VAR" => "hello_from_forge"},
      bootstrap: [
        %{type: "exec", command: "mkdir -p /app"},
        %{type: "file", path: "/app/greeting.txt", content: "Hello from Jido Forge!\n"}
      ]
    }

    case Forge.start_session(session_id, spec) do
      {:ok, _pid} ->
        {:noreply,
         socket
         |> put_flash(:info, "Test session started")
         |> push_navigate(to: ~p"/forge/#{session_id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <div class="max-w-6xl mx-auto py-8 px-4">
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-2xl font-bold">Forge Sessions</h1>
          <div class="flex gap-2">
            <button phx-click="start_test_session" class="btn btn-secondary">
              Test Session
            </button>
            <.link navigate={~p"/forge/new"} class="btn btn-primary">
              New Session
            </.link>
          </div>
        </div>

        <div class="overflow-x-auto">
          <table class="table w-full">
            <thead>
              <tr>
                <th>Session ID</th>
                <th>State</th>
                <th>Iteration</th>
                <th>Started</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={session <- @sessions} id={"session-#{session.session_id}"}>
                <td class="font-mono text-sm">{session.session_id}</td>
                <td><.state_badge state={session.state} /></td>
                <td>{session.iteration}</td>
                <td>{format_time(session.started_at)}</td>
                <td>
                  <.link navigate={~p"/forge/#{session.session_id}"} class="link link-primary">
                    View
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@sessions == []} class="text-center py-12 text-base-content/60">
          No active sessions. <.link navigate={~p"/forge/new"} class="link link-primary">Create one</.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp load_sessions_with_status do
    Forge.list_sessions()
    |> Enum.map(fn id ->
      try do
        case Forge.status(id) do
          {:ok, status} -> status
          _ -> nil
        end
      catch
        :exit, _ -> nil
        _, _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp format_time(nil), do: "—"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(_), do: "—"

  defp state_badge(assigns) do
    {bg, text} = state_colors(assigns.state)
    assigns = assign(assigns, bg: bg, text: text)

    ~H"""
    <span class={["badge", @bg, @text]}>
      {@state}
    </span>
    """
  end

  defp state_colors(:starting), do: {"bg-info/20", "text-info"}
  defp state_colors(:bootstrapping), do: {"bg-info/20", "text-info"}
  defp state_colors(:initializing), do: {"bg-info/20", "text-info"}
  defp state_colors(:ready), do: {"bg-success/20", "text-success"}
  defp state_colors(:running), do: {"bg-warning/20", "text-warning"}
  defp state_colors(:needs_input), do: {"bg-error/20", "text-error"}
  defp state_colors(:stopping), do: {"bg-base-300", "text-base-content/60"}
  defp state_colors(:stopped), do: {"bg-base-300", "text-base-content/60"}
  defp state_colors(_), do: {"bg-base-300", "text-base-content"}
end
