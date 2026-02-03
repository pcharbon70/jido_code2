defmodule AgentJido.GithubIssueBot.PullRequest.Actions.WorkerStartedAction do
  @moduledoc """
  Handles "jido.agent.child.started" signal for pull request workers.

  When a worker starts, sends it the appropriate work request signal
  based on its tag (:patch, :quality, :pr_submit).

  Each worker receives context from previous phases:
  - PatchAgent: issue, triage, research, (optional: previous attempt results)
  - QualityAgent: above + patch result
  - PRSubmitAgent: above + quality result
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

  def run(%{pid: pid, tag: :patch, meta: meta}, _context) do
    Logger.debug("PatchAgent started for attempt #{meta.attempt}")

    signal =
      Signal.new!(
        "patch.request",
        %{
          run_id: meta.run_id,
          issue: meta.issue,
          triage: meta.triage,
          research: meta.research,
          attempt: meta.attempt,
          # For retries, include previous results so agent can learn
          previous_patch: Map.get(meta, :previous_patch, %{}),
          previous_quality: Map.get(meta, :previous_quality, %{})
        },
        source: "/pull_request_coordinator"
      )

    emit_directive = Directive.emit_to_pid(signal, pid)
    {:ok, %{}, [emit_directive]}
  end

  def run(%{pid: pid, tag: :quality, meta: meta}, _context) do
    Logger.debug("QualityAgent started for attempt #{meta.attempt}")

    signal =
      Signal.new!(
        "quality.request",
        %{
          run_id: meta.run_id,
          issue: meta.issue,
          triage: meta.triage,
          research: meta.research,
          patch: meta.patch,
          attempt: meta.attempt
        },
        source: "/pull_request_coordinator"
      )

    emit_directive = Directive.emit_to_pid(signal, pid)
    {:ok, %{}, [emit_directive]}
  end

  def run(%{pid: pid, tag: :pr_submit, meta: meta}, _context) do
    Logger.debug("PRSubmitAgent started")

    signal =
      Signal.new!(
        "pr_submit.request",
        %{
          run_id: meta.run_id,
          issue: meta.issue,
          triage: meta.triage,
          research: meta.research,
          patch: meta.patch,
          quality: meta.quality,
          attempt: meta.attempt
        },
        source: "/pull_request_coordinator"
      )

    emit_directive = Directive.emit_to_pid(signal, pid)
    {:ok, %{}, [emit_directive]}
  end

  # Ignore other child types
  def run(%{tag: tag}, _context) do
    Logger.debug("Unknown pull request worker tag: #{inspect(tag)}")
    {:ok, %{}}
  end
end
