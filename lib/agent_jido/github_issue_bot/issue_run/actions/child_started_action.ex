defmodule AgentJido.GithubIssueBot.IssueRun.Actions.ChildStartedAction do
  @moduledoc """
  Handles "jido.agent.child.started" signal.

  Routes work requests to child agents based on their tag:
  - :triage → sends triage.request
  - :research → sends research.request
  - :pull_request → sends pull_request.request
  """
  use Jido.Action,
    name: "child_started",
    schema: [
      pid: [type: :any, required: true],
      tag: [type: :any, required: true],
      meta: [type: :map, default: %{}]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  require Logger

  # Triage agent started - send triage request
  def run(%{pid: pid, tag: :triage, meta: meta}, _context) do
    Logger.debug("Triage agent started, sending request")

    signal =
      Signal.new!(
        "triage.request",
        %{run_id: meta.run_id, issue: meta.issue},
        source: "/coordinator"
      )

    emit_directive = Directive.emit_to_pid(signal, pid)

    {:ok, %{}, [emit_directive]}
  end

  # Research coordinator started - send research request
  def run(%{pid: pid, tag: :research, meta: meta}, _context) do
    Logger.debug("Research coordinator started, sending request")

    signal =
      Signal.new!(
        "research.request",
        %{
          run_id: meta.run_id,
          issue: meta.issue,
          triage: meta.triage
        },
        source: "/coordinator"
      )

    emit_directive = Directive.emit_to_pid(signal, pid)

    {:ok, %{}, [emit_directive]}
  end

  # PullRequest coordinator started - send pull_request request
  def run(%{pid: pid, tag: :pull_request, meta: meta}, _context) do
    Logger.debug("PullRequest coordinator started, sending request")

    signal =
      Signal.new!(
        "pull_request.request",
        %{
          run_id: meta.run_id,
          issue: meta.issue,
          triage: meta.triage,
          research: meta.research
        },
        source: "/coordinator"
      )

    emit_directive = Directive.emit_to_pid(signal, pid)

    {:ok, %{}, [emit_directive]}
  end

  # Unknown child type - log but don't fail
  def run(%{tag: tag}, _context) do
    Logger.debug("Child started with tag: #{inspect(tag)}")
    {:ok, %{}}
  end
end
