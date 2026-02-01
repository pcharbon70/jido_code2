defmodule AgentJidoWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use AgentJidoWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar bg-base-100 border-b border-base-300 px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <.link navigate={~p"/dashboard"} class="text-xl font-bold hover:opacity-80">Agent Jido</.link>
      </div>
      <div class="flex-none">
        <ul class="flex flex-row px-1 space-x-2 items-center">
          <li>
            <.link navigate={~p"/dashboard"} class="btn btn-ghost btn-sm">Dashboard</.link>
          </li>
          <li>
            <.link navigate={~p"/forge"} class="btn btn-ghost btn-sm">Forge</.link>
          </li>
          <li>
            <.link navigate={~p"/settings"} class="btn btn-ghost btn-sm">Settings</.link>
          </li>
          <li>
            <.theme_toggle />
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-8 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.live_toast_group
      flash={@flash}
      connected={assigns[:socket] != nil}
      corner={:top_right}
      toasts_sync={assigns[:toasts_sync] || []}
    />
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

  @doc """
  Wrapper component for LiveToast.toast_group that loads the module dynamically.
  """
  attr :flash, :map, required: true
  attr :connected, :boolean, required: true
  attr :corner, :atom, default: :bottom_right
  attr :toasts_sync, :list, default: []

  def live_toast_group(assigns) do
    # Dynamically render LiveToast component
    ~H"""
    <div id="toast-group" class="fixed z-50 max-h-screen w-full p-4 md:max-w-[420px] pointer-events-none grid origin-center top-0 right-0 items-start flex-col sm:bottom-auto">
      <.live_component
        :if={@connected}
        module={LiveToast.LiveComponent}
        id="toast-group"
        toasts_sync={@toasts_sync}
        corner={@corner}
        f={@flash}
        kinds={[:info, :error]}
      />
      <div :if={!@connected} id="toast-group">
        <div :for={{kind, msg} <- @flash} class="bg-white group/toast z-100 pointer-events-auto relative w-full items-center justify-between origin-center overflow-hidden rounded-lg p-4 shadow-lg border col-start-1 col-end-1 row-start-1 row-end-2 flex">
          <p class="text-sm">{msg}</p>
        </div>
      </div>
    </div>
    """
  end
end
