# 11 — Onboarding Flow

## Overview

Onboarding initializes a deployable JidoCode instance: owner identity, providers, encrypted secrets, GitHub integration, environment defaults, and first project import.

## First-Run Detection

1. Check for `SystemConfig`.
2. If missing or incomplete, redirect to `/setup`.
3. Resume from persisted step.

## Wizard Steps

### Step 1: Welcome and System Check

- Validate DB connectivity.
- Validate required runtime config presence.
- Show cloud-first deployment context.

### Step 2: Owner Account Bootstrap (AshAuth)

- Create or confirm owner account.
- Enforce single-owner mode.
- Disable open registration for production mode.

### Step 3: Provider and Secret Setup

- Detect env-provided credentials.
- Allow storing operational secrets in encrypted DB references.
- Verify at least one LLM provider.

### Step 4: GitHub App and Webhook Validation

- Validate GitHub App credentials.
- Validate webhook secret and signature path.
- Confirm accessible repositories.

### Step 5: Environment Defaults

- Choose cloud-first default (`:sprite`) or local fallback.
- Validate workspace root for local mode.
- Validate required execution tools for selected mode.

### Step 6: Issue Bot MVP Checks

- Confirm webhook event subscription readiness.
- Configure default Issue Bot policy (enabled/disabled, approval mode).
- Run a webhook simulation validation.

### Step 7: Import First Project

- Select repository and import.
- Initialize workspace and baseline sync.
- Register default workflow and agent configuration.

### Step 8: Complete

- Persist `onboarding_completed`.
- Show next actions (run workflow, review security playbook, test RPC client).

## State Machine

```text
welcome -> owner_bootstrap -> provider_setup -> github_setup -> environment -> issue_bot -> import_project -> complete
```

## Data Updates

- `SystemConfig`: step progression and defaults
- `ProviderCredential`: verification status
- `SecretRef`: encrypted operational secret entries where applicable
- `SupportAgentConfig`: initial Issue Bot config
- `Project`: first import

## Validation Rules

1. Owner account must exist before completion.
2. At least one provider credential must verify.
3. GitHub app or PAT path must verify.
4. Webhook validation must pass for Issue Bot enablement.

## UX Notes

- Each step provides actionable remediation text.
- Security-sensitive values are never echoed back in plaintext.
- Test actions are idempotent and safe to rerun.

## Deferred Enhancements

- richer setup diagnostics
- Tauri-oriented local setup wizard branch
