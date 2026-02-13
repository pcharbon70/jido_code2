defmodule JidoCode.GithubIssueBot.Research.Workers.CodeSearchAgent do
  @dialyzer {:nowarn_function, plugin_specs: 0}
  @moduledoc """
  Worker agent that searches for relevant code in the repository.

  Given an issue, extracts keywords and searches for:
  - Files matching error messages or stack traces
  - Functions/modules mentioned in the issue
  - Related code paths based on classification

  ## Future Implementation

  Will use GitHub Code Search API or local git grep to find relevant code.
  Could become a ReAct agent that iteratively refines search queries.

  ## Current Behavior (Stub)

  Returns mock search results based on issue keywords.
  """
  use Jido.Agent,
    name: "code_search_agent",
    schema: [
      status: [type: :atom, default: :idle],
      run_id: [type: :string, default: nil],
      issue_number: [type: :integer, default: nil]
    ]

  alias JidoCode.GithubIssueBot.Research.Workers.Actions.CodeSearchAction

  def signal_routes(_ctx) do
    [{"code_search.request", CodeSearchAction}]
  end
end
