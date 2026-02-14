defmodule JidoCodeWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.
  """

  require Logger

  import Phoenix.Component
  use JidoCodeWeb, :verified_routes

  # This is used for nested liveviews to fetch the current user.
  # To use, place the following at the top of that liveview:
  # on_mount {JidoCodeWeb.LiveUserAuth, :current_user}
  def on_mount(:current_user, _params, session, socket) do
    {:cont, AshAuthentication.Phoenix.LiveSession.assign_new_resources(socket, session)}
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
      log_auth_boundary(:allow, socket)
      {:cont, socket}
    else
      log_auth_boundary(:deny, socket)
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

  defp log_auth_boundary(:allow, socket) do
    Logger.warning("auth_boundary_check outcome=allow live_view=#{inspect(socket.view)} reason=owner_session_present")
  end

  defp log_auth_boundary(:deny, socket) do
    Logger.warning(
      "auth_boundary_check outcome=deny live_view=#{inspect(socket.view)} reason=missing_or_expired_session"
    )
  end
end
