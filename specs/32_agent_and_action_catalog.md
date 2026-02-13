# 32 — Agent & Action Catalog

## Overview

This catalog defines the agent and action contracts used by JidoCode workflows. MVP includes coding workflows and GitHub Issue Bot workflows.

## Agents

### `JidoCode.Agents.CodingOrchestrator`

- Role: workflow-run coordinator
- Inputs: workflow lifecycle signals
- Outputs: step transition signals, artifact events
- Dependencies: Runic strategy, workflow definitions

### `JidoCode.Agents.ClaudeCodeAgent`

- Role: coding execution in Forge sessions
- Inputs: plan/prompt + workspace context
- Outputs: changed files summary, transcript, cost, diagnostics
- Dependencies: Forge Claude runner, provider credentials

### `JidoCode.Agents.GitHubIssueBot` (MVP)

- Role: triage/research/respond automation for issues
- Triggers: `issues.opened`, `issues.edited`, optional `issue_comment.created`
- Outputs: triage labels, research report, draft response, optional posted response
- Dependencies: GitHub webhook pipeline, support-agent config, workflow triggers

### Phase-tagged agents

- `AmpcodeAgent` (Phase 2)
- `PRReviewBot` (Phase 3)
- `DependencyBot` (Phase 3)

## Product Action Contracts

### Setup & Auth

- `BootstrapOwner`
- `CompleteOnboardingStep`
- `VerifyProviderCredential`
- `RotateSecret`

### Project & Workspace

- `ImportRepo`
- `CloneRepo`
- `SyncRepo`
- `SelectEnvironment`
- `DetectProjectType`

### Workflow & Execution

- `StartWorkflowRun`
- `CancelWorkflowRun`
- `RetryWorkflowRun`
- `RunCodingAgent`
- `RunTests`
- `RequestApproval`

### Git & PR

- `CreateBranch`
- `CommitChanges`
- `PushBranch`
- `CreatePullRequest`
- `CommitAndPR`

### GitHub + Issue Bot

- `VerifyWebhookSignature`
- `HandleWebhookDelivery`
- `FetchGitHubIssue`
- `PostGitHubComment`
- `RunIssueTriage`
- `RunIssueResearch`

### Support Agent Control

- `EnableSupportAgent`
- `DisableSupportAgent`
- `UpdateSupportAgentConfig`

## Action Contract Template (Normative)

Each action definition must include:

1. Input schema
2. Output schema
3. Error schema with typed reason
4. Idempotency behavior
5. Timeout/retry policy
6. Side effects and audit metadata

## Auth and Secret Dependencies

- Actions that access remote providers must declare required secret references.
- Actions requiring user context must declare required actor/auth mode.
- API key/bearer usage is allowed for automation endpoints where defined.

## TypeScript RPC Requirement

Every product action above that is user-facing or automation-facing must be:

1. Publicly callable via Ash action interface.
2. Available via `/rpc/run`.
3. Validatable via `/rpc/validate`.
4. Generated into `assets/js/ash_rpc.ts` with typed signatures.

## Agent-to-Runner Mapping

| Agent | Runner | Forge session |
|---|---|---|
| CodingOrchestrator | coordinator only | No |
| ClaudeCodeAgent | `JidoCode.Forge.Runners.ClaudeCode` | Yes |
| GitHubIssueBot | mixed (LLM + HTTP + optional Forge) | Usually no |
| AmpcodeAgent | `JidoCode.Forge.Runners.Ampcode` | Yes |

## Error Taxonomy

- `:validation_error`
- `:authorization_error`
- `:secret_unavailable`
- `:provider_error`
- `:execution_error`
- `:policy_violation`
- `:timeout`

This taxonomy is shared across workflow and RPC responses.
