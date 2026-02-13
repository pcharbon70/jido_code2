defmodule JidoCodeWeb.PageControllerTest do
  use JidoCodeWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/setup"
  end
end
