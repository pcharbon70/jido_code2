# 03 — Routes and Experience Flows

## Supported Route Catalog

### Browser Routes

| Route | Auth | Phase | Purpose | Primary User Actions |
|---|---|---|---|---|
| `/` | public -> redirect decision | MVP | home and entry routing | continue to setup or dashboard |
| `/setup` | bootstrap/public guarded | MVP | onboarding + owner bootstrap | configure account, secrets, GitHub, environment, first project |
| `/dashboard` | owner session required | MVP | global operations overview | monitor runs, issue bot activity, and system status |
| `/workbench` | owner session required | MVP | cross-project issue/PR operations | view all repos, issues, PRs; launch fix/triage jobs |
| `/projects` | owner session required | MVP | project inventory | search/filter projects, open project detail |
| `/projects/:id` | owner session required | MVP | project-level controls | run workflow, adjust project settings, inspect run history |
| `/projects/:id/runs/:run_id` | owner session required | MVP | run detail + approval | view timeline/logs, approve/reject, inspect artifacts |
| `/workflows` | owner session required | MVP | workflow catalog | choose workflow template, inspect inputs |
| `/agents` | owner session required | MVP | support-agent management | enable/disable Issue Bot, set approval behavior |
| `/settings` | owner session required | MVP | settings hub | navigate provider/security/api sections |
| `/settings/security` | owner session required | MVP | security operations | rotate/revoke credentials, view runbooks and posture |
| `/settings/api` | owner session required | MVP | API/RPC operations | inspect action inventory version, test RPC status |

### API and Integration Routes

| Route | Auth | Phase | Purpose | Primary User/Client Action |
|---|---|---|---|---|
| `POST /rpc/validate` | session or bearer/api key | MVP | contract validation | validate action payload before run |
| `POST /rpc/run` | session or bearer/api key | MVP | action execution | execute public product action |
| `POST /api/github/webhooks` | webhook signature required | MVP | issue and integration triggers | trigger Issue Bot workflows and installation sync |

### Health and Service Routes

| Route | Auth | Phase | Purpose |
|---|---|---|---|
| `/status` (implementation health probe) | public/network-restricted | MVP | deployment health checks |

## Flow F1: First-Run Bootstrap

### Entry

- user opens `/`
- app detects incomplete setup and redirects to `/setup`

### Steps

1. validate system prerequisites
2. bootstrap owner account
3. configure providers and encrypted secret references
4. validate GitHub app and webhook
5. set environment defaults
6. configure Issue Bot baseline policy
7. import first project
8. complete and navigate to `/dashboard`

### Critical UX States

- step-by-step progress indicator
- idempotent test actions
- non-leaky secret handling

## Flow F2: Cross-Project Workbench Operations

### Entry

- user opens `/workbench`

### Steps

1. load all projects with issue and PR summaries
2. filter/sort by backlog, staleness, or risk
3. select issue/PR row and choose action
4. kick off agent job (fix, triage, investigate, follow-up)
5. route to `/projects/:id/runs/:run_id` for live execution

### Required UX Features

- per-row quick actions for kickoff
- visible job kickoff confirmation/failure
- direct links to repo, issue, PR, and run detail

## Flow F3: Run Approval and Ship

### Entry

- run transitions to `awaiting_approval`

### Steps

1. user inspects diff/test summary and risk notes
2. user approves or rejects
3. approved path executes git shipping actions
4. PR artifact captured in run detail

### Guardrails

- policy failure reasons surfaced directly in run UI
- shipping blocked when git safety checks fail

## Flow F4: Issue Bot Webhook to Response

### Entry

- `issues.opened` webhook hits `POST /api/github/webhooks`

### Steps

1. signature + idempotency checks
2. event persisted and routed
3. issue triage workflow run created
4. run visible in `/projects/:id/runs/:run_id`
5. response drafted and optionally approval-gated
6. comment posted to GitHub when policy allows

### Operator Visibility

- `/agents` shows bot trigger health and status
- `/dashboard` and `/workbench` show recent Issue Bot runs

## Flow F5: Security Operations

### Entry

- user opens `/settings/security`

### Steps

1. inspect secret and token status
2. rotate/revoke as needed
3. review incident runbooks
4. audit recent policy violations

### UX Requirements

- clear warning levels
- fast next-step guidance for incidents

## Flow F6: API/RPC Client Operations

### Entry

- user opens `/settings/api` or external client integration path

### Steps

1. verify action inventory version
2. call `POST /rpc/validate`
3. call `POST /rpc/run`
4. inspect result and typed errors

### UX Requirements

- discoverable auth mode requirements
- actionable contract mismatch messaging

## Route Availability by Phase

| Route Group | MVP | Phase 2+ |
|---|---|---|
| onboarding/core operations | yes | yes |
| cross-project workbench | yes | yes |
| issue bot management | yes | yes |
| workflow template expansion | partial | full |
| visual workflow builder routes | no | planned |
| desktop-specific setup routes | no | planned |
