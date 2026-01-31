defmodule AgentJidoWeb.PageController do
  use AgentJidoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def index conn, _params do
    render(conn, :index)
  end
end
