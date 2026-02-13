defmodule JidoCodeWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.
  """

  require Ash.Query

  alias AshAuthentication.Phoenix.LiveSession

  import Phoenix.Component
  use JidoCodeWeb, :verified_routes

  # This is used for nested liveviews to fetch the current user.
  # To use, place the following at the top of that liveview:
  # on_mount {JidoCodeWeb.LiveUserAuth, :current_user}
  def on_mount(:current_user, _params, session, socket) do
    {:cont, LiveSession.assign_new_resources(socket, session)}
  end

  def on_mount(:live_user_optional, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  def on_mount(:live_user_required, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}
    end
  end

  def on_mount(:live_no_user, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  def on_mount(:ensure_onboarding_complete, _params, _session, socket) do
    if onboarding_completed?() do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/setup")}
    end
  end

  def on_mount(:setup_only_until_complete, _params, _session, socket) do
    if onboarding_completed?() do
      destination =
        if socket.assigns[:current_user] do
          ~p"/dashboard"
        else
          ~p"/"
        end

      {:halt, Phoenix.LiveView.redirect(socket, to: destination)}
    else
      {:cont, socket}
    end
  end

  defp onboarding_completed? do
    JidoCode.Setup.SystemConfig
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.Query.limit(1)
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> false
      {:ok, %{onboarding_completed: true}} -> true
      {:ok, _config} -> false
      {:error, _reason} -> false
    end
  rescue
    _ -> false
  end
end
