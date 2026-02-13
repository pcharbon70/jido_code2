defmodule JidoCode.GithubIssueBot.Research.Workers.PRSearchAgent do
  @dialyzer {:nowarn_function, plugin_specs: 0}
  @moduledoc """
  Worker agent that searches for related PRs and issues.

  Searches for:
  - Open PRs that might already fix this issue
  - Closed PRs that might have caused a regression
  - Duplicate issues (open or closed)
  - Related issues with useful context

  ## Future Implementation

  Will use GitHub Search API to find related PRs/issues:
  - Search by keywords from issue title/body
  - Search by file paths from code search results
  - Check for linked issues/PRs

  ## Current Behavior (Stub)

  Returns mock search results.
  """
  use Jido.Agent,
    name: "pr_search_agent",
    schema: [
      status: [type: :atom, default: :idle],
      run_id: [type: :string, default: nil],
      issue_number: [type: :integer, default: nil]
    ]

  alias JidoCode.GithubIssueBot.Research.Workers.Actions.PRSearchAction

  def signal_routes(_ctx) do
    [{"pr_search.request", PRSearchAction}]
  end
end
