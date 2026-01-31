defmodule AgentJido.Jido do
  @moduledoc """
  The Jido instance for AgentJido.

  This module provides the Jido supervisor tree for running agents,
  sensors, and other Jido components within the AgentJido application.

  ## Usage

  The Jido instance is started automatically by the application supervisor.
  You can interact with it via:

      # Start an agent
      {:ok, pid} = AgentJido.Jido.start_agent(MyAgent, id: "my-agent-1")

      # Look up an agent by ID
      pid = AgentJido.Jido.whereis("my-agent-1")

      # List all running agents
      agents = AgentJido.Jido.list_agents()

      # Stop an agent
      :ok = AgentJido.Jido.stop_agent("my-agent-1")
  """

  use Jido, otp_app: :agent_jido
end
