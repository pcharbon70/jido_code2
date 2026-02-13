defmodule JidoCode.GithubIssueBot.Research.Workers.RootCauseAgent do
  @dialyzer {:nowarn_function, plugin_specs: 0}
  @moduledoc """
  Worker agent that hypothesizes the root cause of an issue.

  Analyzes:
  - Issue classification from triage
  - Error messages and stack traces
  - Related code findings (from CodeSearchAgent)
  - Reproduction steps

  ## Future Implementation

  Will use LLM (via jido_ai) to hypothesize root causes:
  - Could become a ReAct agent that iteratively refines hypothesis
  - Would consume results from other workers for context

  ## Current Behavior (Stub)

  Returns a simple hypothesis based on issue classification.
  """
  use Jido.Agent,
    name: "root_cause_agent",
    schema: [
      status: [type: :atom, default: :idle],
      run_id: [type: :string, default: nil],
      issue_number: [type: :integer, default: nil]
    ]

  alias JidoCode.GithubIssueBot.Research.Workers.Actions.RootCauseAction

  def signal_routes(_ctx) do
    [{"root_cause.request", RootCauseAction}]
  end
end
