# GitHub Issue Bot Verification Script
#
# Run with: mix run scripts/test_github_issue_bot.exs
#
# This script verifies the GitHub Issue Bot works correctly,
# running through triage and research phases.

alias AgentJido.GithubIssueBot.CLI.Run

IO.puts("=" |> String.duplicate(60))
IO.puts("GitHub Issue Bot - Verification Script")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# Run with a test issue
result = Run.run(timeout: 15_000)

case result do
  {:ok, state} ->
    IO.puts("")
    IO.puts("✓ Bot completed successfully!")
    IO.puts("")
    IO.puts("Final State:")
    IO.puts("  Phase: #{state.phase}")
    IO.puts("  Run ID: #{state.run_id}")

    if triage = state.artifacts[:triage] do
      IO.puts("")
      IO.puts("Triage Results:")
      IO.puts("  Classification: #{triage.classification}")
      IO.puts("  Needs Info: #{triage.needs_info}")
      IO.puts("  Summary: #{triage.summary}")
    end

    if research = state.artifacts[:research] do
      IO.puts("")
      IO.puts("Research Results:")
      IO.puts("  Workers Completed: #{inspect(research.workers_completed)}")
      IO.puts("  Summary: #{research.summary}")

      if research.root_cause do
        IO.puts("")
        IO.puts("Root Cause Analysis:")
        IO.puts("  Hypothesis: #{research.root_cause.hypothesis}")
        IO.puts("  Confidence: #{research.root_cause.confidence}")
      end
    end

    System.halt(0)

  {:error, reason} ->
    IO.puts("")
    IO.puts("✗ Bot failed: #{inspect(reason)}")
    System.halt(1)
end
