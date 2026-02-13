# JidoCode Forge Overview

Forge is JidoCode's execution subsystem for sandboxed and observable command/agent execution.

This document is an implementation reference and must stay consistent with product-level contracts in:

- `41_forge_integration.md`
- `40_project_environments.md`
- `30_workflow_system_overview.md`

## Core Responsibilities

1. Start and manage execution sessions.
2. Run pluggable runners (shell, Claude, workflow/custom).
3. Stream session output.
4. Persist execution events and state.
5. Enforce concurrency controls.

## Public API Surface

- `start_session/2`
- `stop_session/2`
- `run_iteration/2`
- `run_loop/2`
- `exec/3`
- `cmd/4`
- `apply_input/2`
- `resume/1`
- `cancel/1`
- `create_checkpoint/2`

## Runtime Components

- `JidoCode.Forge.Manager`
- `JidoCode.Forge.SpriteSession`
- `JidoCode.Forge.Runner` behavior
- `JidoCode.Forge.SpriteClient` behavior and implementations
- `JidoCode.Forge.Operations`
- `JidoCode.Forge.PubSub`
- `JidoCode.Forge.Persistence`

## Topic Conventions

- global: `forge:sessions`
- per session: `forge:session:<id>`

## Concurrency Defaults

Refer to `41_forge_integration.md` for normative defaults and product-facing limits.

## Current Boundaries

- Forge focuses on execution semantics.
- Workflow policy, approval logic, and git safety are defined outside Forge specs.
