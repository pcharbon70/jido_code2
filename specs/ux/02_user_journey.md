# 02 — User Journey

## Journey Overview

This journey describes the primary OSS maintainer path from deployment to steady-state issue/PR operations.

## Stage A: Deploy and Bootstrap

### Trigger

The user deploys JidoCode to a cloud VM and opens the app for the first time.

### Goals

1. establish owner access
2. configure providers and integrations
3. import first project

### Routes

- `/setup`

### UX Expectations

1. guided steps with clear validation feedback
2. actionable error states for missing env vars and integration failures
3. no secret value echo in UI

### Exit Criteria

- onboarding complete
- owner account active
- first project imported

## Stage B: Build Initial Project Context

### Trigger

User needs a single operational view across all repos.

### Goals

1. see all projects with issue and PR context
2. identify highest-value work candidates
3. launch fix/triage jobs directly

### Routes

- `/dashboard`
- `/workbench`

### UX Expectations

1. one-screen list of repos with open issue/PR counts and recent activity
2. direct action controls to launch agent jobs
3. clear state updates when job kickoff succeeds/fails

### Exit Criteria

- at least one job launched from workbench
- workbench reflects new run state

## Stage C: Execute Workflow to Pull Request

### Trigger

User starts a workflow from workbench/project context.

### Goals

1. monitor live run state
2. approve and ship safely

### Routes

- `/workbench`
- `/projects/:id`
- `/projects/:id/runs/:run_id`

### UX Expectations

1. run timeline and log streaming are real-time
2. approval gate context is complete (diff/test/policy)
3. git safety failures are explicit and actionable

### Exit Criteria

- run completed with PR created or no-change result

## Stage D: Ongoing Issue and PR Operations

### Trigger

User manages ongoing issue inflow and PR backlog across repos.

### Goals

1. quickly prioritize issues and PRs
2. use Issue Bot and fix jobs in balanced way
3. keep run throughput stable

### Routes

- `/workbench`
- `/agents`
- `/projects/:id/runs/:run_id`

### UX Expectations

1. workbench supports filtering by repo/state/priority
2. recent run outcomes are visible beside issue/PR context
3. bot policy and manual kickoff options are adjacent

### Exit Criteria

- reduced stale issues/PR backlog
- reliable webhook and manual job mix

## Stage E: Security and Incident Handling

### Trigger

Credential rotation, webhook failure, or suspicious activity requires intervention.

### Goals

1. rotate/revoke secrets safely
2. validate webhook authenticity
3. audit automated git side effects

### Routes

- `/settings/security`
- `/projects/:id/runs/:run_id`

### UX Expectations

1. direct links to runbooks and last-known security state
2. high-signal error messages with next-step guidance
3. audit-ready run and policy metadata

### Exit Criteria

- incident resolved
- service returned to healthy operational state

## Stage F: API-Driven Automation

### Trigger

User or automation client needs typed API access to product actions.

### Goals

1. validate action contracts before execution
2. execute actions through RPC with secure auth mode
3. keep generated TS client in sync with action inventory

### Routes

- `/settings/api`
- `POST /rpc/validate`
- `POST /rpc/run`

### UX Expectations

1. discoverable API status and auth expectations
2. explicit validation errors before execution
3. stable contract versioning guidance

### Exit Criteria

- action inventory is fully RPC-callable
- external automation clients can execute approved flows

## Journey Failure Modes

| Failure Point | User Impact | UX Requirement |
|---|---|---|
| Onboarding credential validation fails | blocked setup | inline diagnosis and step-specific remediation |
| Workbench data sync fails | no global operational visibility | stale-state warning + manual refresh + fallback links |
| Webhook signature mismatch | issue bot idle | secure error and retry guidance |
| Workflow step fails | delivery delay | preserve context and expose retry path |
| Git safety policy violation | shipping blocked | explain violated check and required fix |
| RPC contract mismatch | automation breakage | show version mismatch and migration notes |
