# 40 — Project Environments & Workspaces

## Overview

JidoCode executes workflows in project workspaces with a cloud-first default and local fallback.

## Environment Modes

### Sprite/Cloud Workspace (Default)

- primary production execution mode
- isolated runtime per run or per configured pool
- stronger safety boundaries for automation

### Local Workspace (Dev/Fallback)

- host filesystem path
- useful for development and debugging
- must still comply with git safety policy

### Future: Tauri Local App Workspace

- planned packaged local runtime mode
- configuration and secret UX tailored for desktop deployment

## Workspace Interface

All workspace implementations must provide:

1. command execution
2. file read/write/list
3. env injection
4. git status and branch helpers
5. lifecycle cleanup hooks

Return shape:

- `{:ok, result}` or `{:error, reason}` for all callbacks

## Lifecycle

### Provision

- create workspace context
- clone repository
- validate branch baseline

### Pre-Run Prepare

- sync to base branch
- enforce clean-room policy for run branch
- inject required secrets (redaction-aware handling)

### Post-Run

- persist artifacts and status
- cleanup according to mode policy

## Concurrency Policy

- default: one active shipping run per project
- additional runs either queue or use isolated workspaces
- no shared mutable branch context across concurrent shipping runs

## Secret Injection Rules

- source from env and/or encrypted secret refs
- never write plaintext secret files to workspace
- mask sensitive values in all output channels

## Git Auth Rules

- GitHub App token preferred
- PAT fallback allowed
- credential refresh required before push when near expiry

## Directory Baselines

- cloud workspace paths are implementation-defined but must be isolated per run context
- local workspace defaults to configured root under user control

## Safety Coupling

All workspace-driven git operations must comply with `52_git_safety_policy.md`.
