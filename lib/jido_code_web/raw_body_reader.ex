defmodule JidoCodeWeb.RawBodyReader do
  @moduledoc false

  import Plug.Conn, only: [assign: 3]

  @spec read_body(Plug.Conn.t(), keyword()) :: {:ok, binary(), Plug.Conn.t()}
  def read_body(conn, opts), do: read_body(conn, opts, [])

  defp read_body(conn, opts, chunks) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, chunk, conn} ->
        body = IO.iodata_to_binary(Enum.reverse([chunk | chunks]))
        {:ok, body, assign(conn, :raw_body, body)}

      {:more, chunk, conn} ->
        read_body(conn, opts, [chunk | chunks])
    end
  end
end
