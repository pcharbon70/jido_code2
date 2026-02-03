defmodule AgentJido.GithubIssueBot.Research.Actions.WorkerStartedAction do
  @moduledoc """
  Handles "jido.agent.child.started" signal for research workers.

  When a worker starts, sends it the appropriate work request signal
  based on its tag (:code_search, :reproduction, :root_cause, :pr_search).
  """
  use Jido.Action,
    name: "worker_started",
    schema: [
      pid: [type: :any, required: true],
      tag: [type: :any, required: true],
      meta: [type: :map, default: %{}]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  require Logger

  # Map worker tags to their request signal types
  @tag_to_signal %{
    code_search: "code_search.request",
    reproduction: "reproduction.request",
    root_cause: "root_cause.request",
    pr_search: "pr_search.request"
  }

  def run(%{pid: pid, tag: tag, meta: meta}, _context) when is_map_key(@tag_to_signal, tag) do
    signal_type = Map.fetch!(@tag_to_signal, tag)
    Logger.debug("Research worker #{tag} started, sending #{signal_type}")

    signal =
      Signal.new!(
        signal_type,
        %{
          run_id: meta.run_id,
          issue: meta.issue,
          triage: meta.triage
        },
        source: "/research_coordinator"
      )

    emit_directive = Directive.emit_to_pid(signal, pid)

    {:ok, %{}, [emit_directive]}
  end

  # Ignore other child types (shouldn't happen but be defensive)
  def run(%{tag: tag}, _context) do
    Logger.debug("Unknown research worker tag: #{inspect(tag)}")
    {:ok, %{}}
  end
end
