# 41 — Forge Integration

## Overview

Forge is JidoCode's execution substrate for coding and shell steps. Workflow runs map execution steps to Forge sessions with streamed output and persisted state.

## Workflow-to-Forge Mapping

| Workflow Step Type | Forge Session |
|---|---|
| Coding agent step | yes |
| Shell/test step | yes |
| LLM-only step | no |
| Approval step | no |

## Session Configuration

Each Forge session created by workflow execution includes:

1. runner type
2. runner config
3. workspace context
4. env injection map
5. bootstrap commands
6. run correlation metadata

## Streaming and Events

Run detail UI subscribes to:

- `jido_code:run:<run_id>`
- `forge:session:<session_id>`

Required handling:

- subscribe on active step start
- unsubscribe on step completion
- preserve log continuity in run artifacts

## Concurrency Defaults

- max total sessions: 10
- max claude sessions: 3
- max shell sessions: 5
- max issue-bot-related execution sessions: 3

These values are configurable via system settings.

## Failure Handling

- startup/provision failure: retry once then fail step
- runner timeout: fail step with typed timeout error
- session crash: mark step failed and preserve partial output
- output parse error: warn and continue unless parser contract requires fail-fast

## Checkpointing

MVP does not require resume for correctness.

- Step-level retry and run-level retry semantics are controlled by workflow contract.
- Checkpoint support can improve recovery in later phases.

## Issue Bot Integration

Issue Bot workflow steps may use Forge when executing local reproduction or code inspection tasks. Pure API/LLM steps may bypass Forge.

## Naming and Module Consistency

All references must use `JidoCode.Forge.*` namespace.
