# 30 — Workflow System Overview

## Overview

JidoCode workflows are durable Runic DAGs that orchestrate coding and support-agent execution across Forge sessions, LLM calls, and human approval gates.

## Workflow Runtime Model

```text
WorkflowDefinition (versioned)
  -> WorkflowRun (version pinned at creation)
    -> Step execution (Forge, LLM, or control)
      -> Artifacts + events + status transitions
```

## Trigger Types

| Trigger | MVP | Notes |
|---|---|---|
| Manual | Yes | User starts run from UI |
| Webhook | Yes | Includes Issue Bot `issues.*` paths |
| Support Agent | Yes | Agent-generated triggers |
| Schedule | No | Phase 2+ |

## Step Categories

1. Forge-backed execution step (coding, shell)
2. LLM-only reasoning step
3. Approval step (blocking)
4. Control step (branching/routing)

## Status Lifecycle

```text
pending -> running -> awaiting_approval -> running -> completed
pending -> running -> failed
pending -> running -> cancelled
```

## Approval Semantics

- Approval nodes transition run to `awaiting_approval`.
- Approval payload includes diff summary, test output summary, and risk notes.
- `approve` continues.
- `reject` cancels run (or routes to configured retry node if defined).

## Retry Semantics (Normative)

- Default retry policy: **full-run retry**.
- Step-level retry is allowed only when explicitly defined by workflow contract.
- Retries must preserve previous failure artifacts and reason codes.

## Event Contract (Normative)

Topic: `jido_code:run:<run_id>`

Required events:

- `run_started`
- `step_started`
- `step_completed`
- `step_failed`
- `approval_requested`
- `approval_granted`
- `approval_rejected`
- `run_completed`
- `run_failed`
- `run_cancelled`

Each event must include:

- `run_id`
- `workflow_name`
- `workflow_version`
- `timestamp`
- `correlation_id`

## Workflow Versioning

- Builtin and custom workflows are versioned integers.
- Each run pins the version at start time.
- Updates create new versions; old runs keep original behavior.

## Data Flow

- Upstream step outputs become structured facts available to downstream nodes.
- Artifacts are produced incrementally and linked to workflow run and step.
- Redaction applies before fact persistence when content may contain sensitive values.

## Issue Bot Integration (MVP)

Webhook event path:

1. GitHub webhook validated and persisted.
2. Trigger mapped to Issue Bot workflow definition.
3. Support-agent configuration evaluated.
4. Workflow run created with trigger metadata.
5. Run executes triage/research/respond sequence with approval policy.

## Failure Model

- Failures are typed (`validation`, `execution`, `auth`, `timeout`, `policy_violation`).
- Typed failures map to user-facing remediation hints.
- Failure context must include last successful step and safe retry recommendation.

## Observability Requirements

- Run timeline with per-step duration and state.
- Session output streaming for active Forge-backed steps.
- Artifact browser for logs, reports, and PR outputs.
- Policy check outcomes visible to users before shipping.

## Deferred Features (Phase 2+)

- Scheduled triggers
- Complex dynamic sub-DAG generation
- Advanced per-step backoff strategies
- Multi-repo orchestration
