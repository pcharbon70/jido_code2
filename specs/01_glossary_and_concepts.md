# 01 — Glossary & Concepts

## Core Terms

### JidoCode

The product described by this spec set: a single-user coding orchestrator with durable workflows, policy-gated shipping, and typed RPC APIs.

### Agent

A Jido agent that processes signals and executes actions (coding, triage, research, coordination).

### Action

A validated, composable unit of work with explicit inputs/outputs and failure contracts.

### Workflow

A durable Runic DAG composed of action nodes and control/approval nodes.

### Workflow Run

A concrete execution instance of a version-pinned workflow definition.

### Runner

Forge execution adapter (for example `shell`, `claude_code`, custom).

### Forge Session

Execution runtime for runner-backed workflow steps, with streaming output and persisted events.

### Project

Imported repository plus configuration required for workflows and support agents.

### Workspace

Execution environment bound to a project (`:sprite` cloud default, `:local` fallback).

### Artifact

Persisted workflow output (logs, summaries, diff stats, PR metadata, reports).

### Support Agent

Long-lived automation component configured per project (MVP includes GitHub Issue Bot).

### Secret Reference

Encrypted operational secret record used by integrations and execution steps.

### Product Action Inventory

Normative list of public actions that must be exposed via typed Ash TypeScript RPC.

## Conceptual Architecture

```text
LiveView UI + RPC Clients
  -> Ash Actions (public contracts)
    -> Workflow Orchestration (Runic)
      -> Forge Execution + Integrations
        -> Postgres (Ash domains, encrypted secret refs, run history)
```

## Relationship Map

```text
Project -> WorkflowDefinition -> WorkflowRun -> Artifact
Project -> SupportAgentConfig -> webhook-triggered WorkflowRun
WorkflowRun -> ForgeSession(s)
WorkflowRun -> PullRequest (optional)
SecretRef -> provider/workspace/integration usage
```
