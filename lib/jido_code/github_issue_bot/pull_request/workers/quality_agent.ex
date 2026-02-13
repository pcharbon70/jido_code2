defmodule JidoCode.GithubIssueBot.PullRequest.Workers.QualityAgent do
  @dialyzer {:nowarn_function, plugin_specs: 0}
  @moduledoc """
  Worker agent that validates the code fix quality.

  Runs quality checks on the patched code:
  - Unit tests
  - Linting (credo, etc.)
  - Type checking (dialyzer)
  - Any project-specific checks

  ## Future Implementation

  Will execute actual CI commands:
  1. Run `mix test` or equivalent
  2. Run `mix credo` for linting
  3. Run `mix dialyzer` for type checking
  4. Collect and parse results

  Could integrate with GitHub Actions or run locally.

  ## Current Behavior (Stub)

  Returns mock quality results (usually passing).
  """
  use Jido.Agent,
    name: "quality_agent",
    schema: [
      status: [type: :atom, default: :idle],
      run_id: [type: :string, default: nil],
      issue_number: [type: :integer, default: nil]
    ]

  alias JidoCode.GithubIssueBot.PullRequest.Workers.Actions.QualityAction

  def signal_routes(_ctx) do
    [{"quality.request", QualityAction}]
  end
end
