# 10 — Web UI & Routes

## Information Architecture

```text
/                              -> Home / dashboard entry
/setup                         -> onboarding and owner bootstrap
/dashboard                     -> project and run overview
/workbench                     -> all projects + issues + PRs + agent job kickoff
/projects                      -> project list
/projects/:id                  -> project detail
/projects/:id/runs/:run_id     -> workflow run detail
/workflows                     -> workflow definitions
/agents                        -> support agents (Issue Bot MVP)
/settings                      -> settings home
/settings/security             -> security help and operational guidance
/settings/api                  -> RPC/API and integration status
```

## Route Model

### Browser Routes (AshAuth Protected)

- LiveView pages require authenticated owner session except explicitly public onboarding bootstrap cases.
- CSRF protection applies to browser mutating requests.

### API/RPC Routes

- `POST /rpc/run`
- `POST /rpc/validate`
- API actor may be resolved by session, bearer token, or API key as allowed by action policy.

### Webhook Route

- `POST /api/github/webhooks`
- Signature verification and idempotency required.

## Page Requirements

### Dashboard

- Recent runs and status
- project health
- issue bot activity summary
- security posture indicators (last secret rotation, webhook health)

### Workbench (`/workbench`)

- Cross-project operations table for all imported GitHub repositories
- Per project: open issue count, open PR count, stale indicators, latest run status
- Issue/PR row actions:
  - kickoff fix workflow
  - kickoff triage/research workflow
  - kickoff follow-up job (investigate, retest, regenerate response)
- Fast links to:
  - GitHub issue/PR URL
  - local project detail
  - active/newly created run detail

### Onboarding (`/setup`)

- owner bootstrap
- provider and GitHub setup
- secret configuration
- environment defaults
- import first project

### Support Agents (`/agents`)

- enable/disable Issue Bot per project
- webhook trigger status
- approval policy display

### Settings Security (`/settings/security`)

- security playbook links
- secret lifecycle actions
- token/key status
- audit trail summary links

### Settings API (`/settings/api`)

- RPC endpoint status
- action inventory version
- generated TS client status

## Live Real-Time Requirements

| Page | Topic | Events |
|---|---|---|
| Run detail | `jido_code:run:<id>` | step transitions, approval, completion |
| Run detail | `forge:session:<id>` | streaming output and session status |
| Dashboard | `jido_code:runs` | run started/completed/failed |
| Workbench | `jido_code:workbench` | project issue/PR updates, run kickoff state |
| Agents | `jido_code:agents` | issue bot trigger and run outcomes |

## UX Rules

1. All mutating actions expose explicit confirmation/error states.
2. Approval decisions show context summary and policy warnings.
3. Security-relevant failures are clear and actionable.
4. Critical controls include stable DOM IDs for LiveView tests.

## Naming Rule

All UI copy and route docs must use `JidoCode` as the product name.
