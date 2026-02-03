defmodule AgentJido.GithubIssueBot.Triage.TriageAgent do
  @moduledoc """
  Triage agent that classifies issues.

  Receives issue data, analyzes it, and reports back to parent coordinator.
  Currently uses a simple heuristic-based classification (no LLM).
  """
  use Jido.Agent,
    name: "triage_agent",
    schema: [
      status: [type: :atom, default: :idle],
      run_id: [type: :string, default: nil],
      issue_number: [type: :integer, default: nil]
    ]

  alias AgentJido.GithubIssueBot.Triage.Actions.TriageAction

  def signal_routes do
    [{"triage.request", TriageAction}]
  end
end
