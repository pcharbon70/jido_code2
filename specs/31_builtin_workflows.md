# 31 — Builtin Workflows

## Overview

JidoCode ships builtin workflows that are implementation-ready reference contracts.

## MVP Workflow 1: Implement Task

- Name: `implement_task`
- Trigger: manual
- Purpose: plan -> implement -> test -> approve -> commit/pr

### Steps

1. `PlanTask`
2. `RunCodingAgent`
3. `RunTests`
4. `RequestApproval`
5. `CommitAndPR`

### Required outputs

- implementation summary
- test summary
- diff summary
- PR artifact

## MVP Workflow 2: Fix Failing Tests

- Name: `fix_failing_tests`
- Trigger: manual
- Purpose: reproduce -> diagnose -> fix -> verify -> approve -> commit/pr

### Steps

1. `ReproduceFailure`
2. `DiagnoseFailure`
3. `RunCodingAgent`
4. `RunTests`
5. `RequestApproval`
6. `CommitAndPR`

### Failure contract

- if reproduction does not fail, run exits as `no_changes_needed`
- if verification fails after configured retry budget, run transitions to `failed`

## MVP Workflow 3: Issue Triage & Research

- Name: `issue_triage`
- Trigger: webhook (`issues.opened`, `issues.edited`) and manual
- Purpose: triage issue, produce research-backed response, optionally post comment

### Steps

1. `FetchGitHubIssue`
2. `RunIssueTriage`
3. `RunIssueResearch`
4. `ComposeIssueResponse`
5. `RequestApproval` (unless policy allows auto-post)
6. `PostGitHubComment`

### Required artifacts

- triage classification
- research summary
- proposed response text
- posted comment URL (when posted)

## Phase 2+ Workflows

### `research_and_implement` (Phase 2)

Advanced multi-phase research/design/execution pipeline.

### `code_review` (Phase 3)

Automated PR review workflow.

## Shared Contract Rules

1. Workflow definition version is pinned at run creation.
2. Approval nodes must include context payload.
3. Git shipping nodes must pass checks from spec 52.
4. All user-triggerable and automation-triggerable actions must be RPC-callable.

## Registration

Builtin workflows are registered on startup and updated by versioned upsert behavior.
