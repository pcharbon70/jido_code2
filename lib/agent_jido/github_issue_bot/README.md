# GitHub Issue Bot - Phase 1 & 2 Implementation

A multi-phase implementation of the GitHub Issue Bot using Jido's orchestration patterns.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         CoordinatorAgent                                  │
│                    (owns lifecycle of one issue)                          │
│                                                                           │
│  Signals:                                                                 │
│  - issue.start → spawn TriageAgent                                       │
│  - triage.result → spawn ResearchCoordinator                             │
│  - research.result → complete (future: spawn PatchAgent)                 │
└─────────────────────────────┬────────────────────────────────────────────┘
                              │
            ┌─────────────────┴─────────────────┐
            │                                   │
    ┌───────▼───────┐               ┌───────────▼───────────┐
    │  TriageAgent  │               │  ResearchCoordinator  │
    │  (classifies) │               │    (fans out to 4)    │
    └───────┬───────┘               └───────────┬───────────┘
            │                                   │
    triage.result                    ┌──────────┼──────────┐
            │                        │          │          │
            └────────────►   ┌───────▼──┐ ┌─────▼────┐ ┌───▼─────┐
                             │CodeSearch│ │RootCause │ │PRSearch │
                             └──────────┘ └──────────┘ └─────────┘
                                          ┌──────────┐
                                          │Repro     │
                                          └──────────┘
```

## Current Features

### Phase 1: Triage
- **Coordinator spawns triage child** on `issue.start` signal
- **Triage agent classifies issues** using simple heuristics:
  - Bug detection (title/labels)
  - Feature/enhancement detection
  - Question detection
  - Documentation detection
  - `needs_info` flag based on body content
- **Results bubble up** via `emit_to_parent`
- **Idempotent result handling** (duplicates ignored)

### Phase 2: Research
- **Research coordinator fans out to 4 parallel workers**:
  - `CodeSearchAgent` - finds relevant code files (stub)
  - `ReproductionAgent` - extracts repro steps and environment
  - `RootCauseAgent` - hypothesizes root cause
  - `PRSearchAgent` - finds related PRs/issues (stub)
- **Workers run in parallel** and report back to coordinator
- **Results aggregated** into a research report artifact
- **CLI runner** for debugging

## Usage

### Run with CLI

```bash
mix run -e "AgentJido.GithubIssueBot.CLI.Run.run()"
```

### Interactive debugging

```bash
iex -S mix
iex> AgentJido.GithubIssueBot.CLI.Run.run()
```

### Custom issue

```elixir
issue = %{
  repo: "myorg/myrepo",
  number: 42,
  title: "Feature: Add dark mode",
  body: "Please add dark mode support",
  labels: ["enhancement"]
}

AgentJido.GithubIssueBot.CLI.Run.run(issue: issue)
```

## Running Tests

```bash
mix test test/agent_jido/github_issue_bot/
```

## File Structure

```
lib/agent_jido/github_issue_bot/
├── cli/
│   └── run.ex                        # CLI runner for debugging
├── issue_run/
│   ├── coordinator_agent.ex          # Main coordinator agent
│   └── actions/
│       ├── start_run_action.ex       # Handles issue.start
│       ├── child_started_action.ex   # Handles child.started
│       ├── triage_result_action.ex   # Handles triage.result
│       └── research_result_action.ex # Handles research.result
├── triage/
│   ├── triage_agent.ex               # Triage worker agent
│   └── actions/
│       └── triage_action.ex          # Performs classification
└── research/
    ├── research_coordinator.ex       # Research coordinator (fans out)
    ├── actions/
    │   ├── start_research_action.ex  # Spawns 4 workers
    │   ├── worker_started_action.ex  # Routes requests to workers
    │   └── worker_result_action.ex   # Aggregates worker results
    └── workers/
        ├── code_search_agent.ex      # Searches for relevant code
        ├── reproduction_agent.ex     # Extracts repro steps
        ├── root_cause_agent.ex       # Hypothesizes root cause
        ├── pr_search_agent.ex        # Finds related PRs/issues
        └── actions/
            ├── code_search_action.ex
            ├── reproduction_action.ex
            ├── root_cause_action.ex
            └── pr_search_action.ex

test/agent_jido/github_issue_bot/
├── issue_run/
│   └── coordinator_test.exs          # Coordinator integration tests
└── research/
    └── research_coordinator_test.exs # Research phase tests
```

## Coordinator State

```elixir
%{
  run_id: "run-123456",
  phase: :idle | :awaiting_triage | :awaiting_research | :needs_info | :completed,
  issue: %{repo: ..., number: ..., title: ..., body: ..., labels: [...]},
  children: %{},
  artifacts: %{
    triage: %{
      classification: :bug | :feature | :question | :documentation | :unknown,
      needs_info: boolean(),
      summary: String.t(),
      completed_at: DateTime.t()
    },
    research: %{
      workers_completed: [:code_search, :reproduction, :root_cause, :pr_search],
      code_search: %{keywords: [...], files: [...], summary: ...},
      reproduction: %{has_repro_steps: boolean(), steps: [...], environment: %{...}},
      root_cause: %{hypothesis: String.t(), confidence: :high | :medium | :low, evidence: [...]},
      pr_search: %{related_prs: [...], related_issues: [...], summary: ...},
      summary: String.t(),
      completed_at: DateTime.t()
    }
  },
  errors: []
}
```

## Next Steps (Phase 3+)

1. ~~**Triage Phase**~~ ✅ - Classify issues, detect needs_info

2. ~~**Research Phase**~~ ✅ - Fan-out to 4 workers, aggregate findings

3. **Patch Phase** - Add PatchAgent for implementing fixes

4. **Quality Phase** - Add QualityAgent for running tests/lint

5. **Submit Phase** - Add PRSubmitAgent for creating PRs

6. **Real Implementations** - Replace stubs with:
   - GitHub Code Search API for CodeSearchAgent
   - GitHub Search API for PRSearchAgent
   - LLM (via jido_ai) for RootCauseAgent

7. **BT Layer** - Consider adding behavior tree layer when phases > 3
