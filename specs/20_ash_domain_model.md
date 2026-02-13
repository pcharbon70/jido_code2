# 20 — Ash Domain Model

## Overview

JidoCode uses Ash + Postgres as the canonical system of record. This model supports single-user auth, encrypted operational secrets, workflow orchestration, project execution, and typed RPC exposure.

## Domain Map

| Domain | Purpose |
|---|---|
| `JidoCode.Accounts` | AshAuth single-user identity and API access |
| `JidoCode.Setup` | Onboarding state and instance-level configuration |
| `JidoCode.Projects` | Imported repos, workspace bindings, project settings |
| `JidoCode.Orchestration` | Workflow definitions, runs, artifacts, approvals, PRs |
| `JidoCode.GitHub` | GitHub repo metadata, webhooks, issue analysis |
| `JidoCode.Agents` | Support agent configs and trigger policies |
| `JidoCode.Forge.Domain` | Execution session persistence and events |

## Auth Model (AshAuth Single-User)

### `Accounts.User`

- One owner account per instance.
- Production policy disables open registration actions.
- Session and token strategies remain available for browser/API use.

### `Accounts.ApiKey` and `Accounts.Token`

- API automation credentials.
- Revocation and expiry must be first-class actions.

## Setup Domain

### `SystemConfig` (singleton)

```text
id                        :uuid PK
onboarding_completed       :boolean
onboarding_step            :integer
deployment_mode            :atom [:cloud_vm, :local]
default_environment        :atom [:sprite, :local]
workspace_root             :string
owner_bootstrapped_at      :utc_datetime_usec
rpc_inventory_version      :integer
inserted_at                :utc_datetime_usec
updated_at                 :utc_datetime_usec
```

### `ProviderCredential`

Metadata for provider credentials and health state.

```text
id                        :uuid PK
provider                   :atom [:anthropic, :openai, :google, :github_app, :github_pat, :sprites]
status                     :atom [:active, :invalid, :not_set, :rotating]
verified_at                :utc_datetime_usec
metadata                   :map
inserted_at                :utc_datetime_usec
updated_at                 :utc_datetime_usec
```

### `SecretRef` (encrypted secret store)

Operational secrets stored encrypted at rest.

```text
id                        :uuid PK
scope                      :atom [:instance, :project, :integration]
name                       :string
ciphertext                 :string   # encrypted via ash_cloak
key_version                :integer
source                     :atom [:env, :onboarding, :rotation]
last_rotated_at            :utc_datetime_usec
expires_at                 :utc_datetime_usec nullable
inserted_at                :utc_datetime_usec
updated_at                 :utc_datetime_usec
```

Rules:

1. `ciphertext` fields are always encrypted.
2. Plain secret values are never persisted in non-encrypted columns.
3. Sensitive outputs are redacted before persistence.

## Projects Domain

### `Project`

```text
id                        :uuid PK
name                       :string
github_full_name           :string unique
default_branch             :string
environment_type           :atom [:sprite, :local]
workspace_path             :string nullable
clone_status               :atom [:pending, :cloning, :ready, :error]
settings                   :map
last_synced_at             :utc_datetime_usec
inserted_at                :utc_datetime_usec
updated_at                 :utc_datetime_usec
```

### `ProjectSecretBinding`

Maps project runtime variables to secret refs.

```text
id                        :uuid PK
project_id                 :uuid FK
env_var_name               :string
secret_ref_id              :uuid FK
inject_to_workspace        :boolean
inserted_at                :utc_datetime_usec
updated_at                 :utc_datetime_usec
```

## Orchestration Domain

### `WorkflowDefinition`

```text
id                        :uuid PK
name                       :string unique
category                   :atom [:builtin, :custom]
version                    :integer
definition                 :map
input_schema               :map
approval_policy            :map
trigger_types              :list [:manual, :webhook, :schedule, :support_agent]
inserted_at                :utc_datetime_usec
updated_at                 :utc_datetime_usec
```

### `WorkflowRun`

```text
id                        :uuid PK
project_id                 :uuid FK
workflow_definition_id     :uuid FK
status                     :atom [:pending, :running, :awaiting_approval, :completed, :failed, :cancelled]
trigger                    :atom [:manual, :webhook, :schedule, :support_agent]
inputs                     :map
current_step               :string
step_results               :map
error                      :map nullable
started_at                 :utc_datetime_usec
completed_at               :utc_datetime_usec nullable
inserted_at                :utc_datetime_usec
updated_at                 :utc_datetime_usec
```

### `Artifact`

Artifacts include logs, diffs, reports, and PR details with redacted payload content.

### `PullRequest`

Tracks shipping outputs and lifecycle synchronization.

## GitHub Domain

- Keep `Repo`, `WebhookDelivery`, `IssueAnalysis`.
- Webhook secrets and tokens move to encrypted secret references instead of plaintext fields.

## Agents Domain

### `SupportAgentConfig`

Per-project bot configuration.

```text
id                        :uuid PK
project_id                 :uuid FK
agent_type                 :atom [:github_issue_bot, :pr_review_bot, :dependency_bot]
enabled                    :boolean
webhook_events             :list
configuration              :map
approval_policy            :map
last_triggered_at          :utc_datetime_usec
inserted_at                :utc_datetime_usec
updated_at                 :utc_datetime_usec
```

## Product Action Inventory for TypeScript RPC

The following action groups are mandatory RPC coverage:

1. Setup and onboarding actions
2. Project import/sync/workspace actions
3. Workflow run lifecycle actions
4. Approval actions
5. Git/PR actions
6. GitHub webhook and issue-bot control actions
7. Support-agent config actions
8. Required Forge orchestration actions used in product UI

## Data Classification

| Class | Example | Storage |
|---|---|---|
| Encrypted | webhook secret, installation token | encrypted DB field |
| Derived | verified timestamp, expiry metadata | plaintext DB |
| Public operational | run status, branch name | plaintext DB |

## Retention Guidelines

| Resource | Default Retention |
|---|---|
| WorkflowRun | indefinite |
| Artifact logs | 30 days |
| Forge events | 7 days |
| Webhook deliveries | 30 days |
| Secret history metadata | indefinite |

## Indexes

- `Project(github_full_name)` unique
- `WorkflowRun(project_id, inserted_at DESC)`
- `WorkflowRun(status, inserted_at DESC)`
- `SupportAgentConfig(project_id, agent_type)` unique
- `SecretRef(scope, name)` unique
