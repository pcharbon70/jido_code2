defmodule JidoCodeWeb.SetupLive do
  use JidoCodeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="mx-auto max-w-3xl rounded-xl border border-base-300 bg-base-100 p-8 shadow-sm">
        <h1 class="text-3xl font-semibold tracking-tight text-base-content">Setup</h1>
        <p class="mt-3 text-base text-base-content/70">
          First-run onboarding is required before accessing the rest of the app.
        </p>
      </section>
    </Layouts.app>
    """
  end
end
