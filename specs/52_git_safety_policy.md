# 52 — Git Safety Policy

## Overview

This policy is mandatory for all git side effects initiated by JidoCode workflows and support agents.

## Allowed Operations by Phase

### Pre-Run

- fetch/sync base branch
- verify workspace cleanliness
- establish run branch context

### Pre-Ship

- stage changes
- generate diff and policy scan
- prepare commit metadata

### Ship

- commit
- push
- create PR

## Forbidden Defaults

1. force push (`--force`, `--force-with-lease`) without explicit emergency override flow.
2. destructive reset/clean outside isolated ephemeral workspace policy.
3. implicit branch deletion after PR without policy-configured opt-in.
4. committing when secret scan fails.

## Mandatory Checks

Before commit/push/PR:

1. workspace policy check (dirty tree handling by mode)
2. branch collision check
3. secret scan check
4. diff size threshold check
5. binary file policy check
6. policy authorization check (workflow/agent allowed to ship)

## Recovery Semantics

| Failure | Response |
|---|---|
| push auth failure | refresh credentials and retry once |
| branch exists | create deterministic suffix and retry once |
| PR API 422 | persist branch artifact, mark action failed |
| secret scan fail | block shipping, mark policy violation |
| large diff threshold exceed | block or require explicit approval override |

## Auditability Requirements

For each git side effect, persist:

- command intent
- command result code
- actor/workflow/run identifiers
- timestamp
- policy-check outcomes

## Idempotency and Safety

- retries must not create duplicate PRs for same branch unless policy allows.
- duplicate push attempts must be detectable and logged.

## Relationship to Other Specs

- Happy path: `51_git_and_pr_flow.md`
- Security: `60_security_and_auth.md`
- Operational runbooks: `62_security_playbook.md`
