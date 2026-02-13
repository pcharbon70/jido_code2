defmodule JidoCode.GithubIssueBot.PullRequest.Workers.PRSubmitAgent do
  @dialyzer {:nowarn_function, plugin_specs: 0}
  @moduledoc """
  Worker agent that creates the pull request on GitHub.

  Given the patch and quality results, creates:
  - A pull request with descriptive title and body
  - Links back to the original issue
  - Labels based on triage classification

  ## Future Implementation

  Will use GitHub API to:
  1. Push the branch if needed
  2. Create a pull request
  3. Add labels and reviewers
  4. Link to the original issue

  ## Current Behavior (Stub)

  Returns mock PR data with generated title and URL.
  """
  use Jido.Agent,
    name: "pr_submit_agent",
    schema: [
      status: [type: :atom, default: :idle],
      run_id: [type: :string, default: nil],
      issue_number: [type: :integer, default: nil]
    ]

  alias JidoCode.GithubIssueBot.PullRequest.Workers.Actions.PRSubmitAction

  def signal_routes(_ctx) do
    [{"pr_submit.request", PRSubmitAction}]
  end
end
