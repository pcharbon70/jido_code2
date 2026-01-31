defmodule AgentJidoWeb.AshTypescriptRpcController do
  use AgentJidoWeb, :controller

  def run(conn, params) do
    result = AshTypescript.Rpc.run_action(:agent_jido, conn, params)
    json(conn, result)
  end

  def validate(conn, params) do
    result = AshTypescript.Rpc.validate_action(:agent_jido, conn, params)
    json(conn, result)
  end
end
