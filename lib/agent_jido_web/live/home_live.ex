defmodule AgentJidoWeb.HomeLive do
  use AgentJidoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns[:current_user] do
      {:ok, Phoenix.LiveView.redirect(socket, to: ~p"/dashboard")}
    else
      {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gradient-to-br from-base-200 to-base-300">
      <div class="w-full max-w-md px-6">
        <div class="text-center mb-8">
          <h1 class="text-4xl font-bold text-base-content">Agent Jido</h1>
          <p class="mt-2 text-base-content/70">AI Agent Platform</p>
        </div>
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <%= if @current_user do %>
              <p class="text-center text-lg mb-4">Welcome, {@current_user.email}</p>
              <a href="/dashboard" class="btn btn-primary btn-block">Go to Dashboard</a>
              <a href="/sign-out" class="btn btn-outline btn-block mt-2">Sign Out</a>
            <% else %>
              <a href="/sign-in" class="btn btn-primary btn-block">Sign In</a>
              <div class="divider">OR</div>
              <a href="/register" class="btn btn-outline btn-block">Create Account</a>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
