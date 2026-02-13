defmodule JidoCode.GithubIssueBot.Research.Workers.ReproductionAgent do
  @dialyzer {:nowarn_function, plugin_specs: 0}
  @moduledoc """
  Worker agent that analyzes reproduction steps from the issue.

  Parses the issue body to extract:
  - Step-by-step reproduction instructions
  - Environment requirements (versions, OS, etc.)
  - Expected vs actual behavior
  - Minimal reproduction case (if provided)

  ## Future Implementation

  Could use LLM to extract structured repro steps from unstructured text.
  Could attempt to validate repro steps are complete and actionable.

  ## Current Behavior (Stub)

  Extracts reproduction info using simple heuristics.
  """
  use Jido.Agent,
    name: "reproduction_agent",
    schema: [
      status: [type: :atom, default: :idle],
      run_id: [type: :string, default: nil],
      issue_number: [type: :integer, default: nil]
    ]

  alias JidoCode.GithubIssueBot.Research.Workers.Actions.ReproductionAction

  def signal_routes(_ctx) do
    [{"reproduction.request", ReproductionAction}]
  end
end
