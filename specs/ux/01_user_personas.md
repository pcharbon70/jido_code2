# 01 — User Personas

## Product Constraint (Applies to All Personas)

JidoCode is **single-user only** for this product phase.

- one owner/operator per instance
- no orgs, no RBAC, no tenant partitioning
- no multi-tenant administration workflows

## Persona P1: OSS Maintainer (Primary)

### Profile

- Role: maintainer of public or internal OSS repositories
- Repos managed: 3-20
- Main pain surface: issue and PR operational load
- Deployment preference: cloud VM (Fly-style)

### Goals

1. see all repos, open issues, and open PRs in one place
2. quickly kick off agent-driven fix/triage jobs from that view
3. keep automation safe with approvals and policy checks
4. reduce issue backlog without losing response quality

### Pain Points

1. high issue volume and duplicated reports
2. context switching repo-by-repo for triage and follow-up
3. manual handoff from issue discovery to coding/fix execution
4. concern about bot actions that bypass guardrails

### Success Signals

- cross-project workbench gives one-screen status of repos/issues/PRs
- webhook and manual kickoffs both create reliable runs
- issue-to-fix workflow latency decreases over time
- policy failures are clear and non-destructive

### Core Routes Used

- `/dashboard`
- `/workbench`
- `/projects/:id`
- `/projects/:id/runs/:run_id`
- `/agents`
- `/settings/security`

## Persona P2: Solo Developer / Small Team Lead (Secondary)

### Profile

- Role: solo developer or lead running one JidoCode instance
- Team size: 1-6 engineers
- Repos managed: 2-12

### Goals

1. ship routine code changes with less manual toil
2. reduce cycle time from task to pull request
3. keep automation visible and controllable
4. maintain confidence in security and git safety

### Pain Points

1. repetitive implementation/refactor tasks
2. context switching between coding, testing, git, and GitHub
3. workflow failures that require manual diagnosis

### Success Signals

- first successful workflow run within 15 minutes
- consistent PR generation from approved runs
- clear audit trail for automated side effects

### Core Routes Used

- `/setup`
- `/dashboard`
- `/workbench`
- `/projects`
- `/projects/:id/runs/:run_id`
- `/settings/api`

## Persona P3: Security-Conscious Engineering Lead (Supporting)

### Profile

- Role: single-user operator with strict security posture
- Focus: secrets, webhook authenticity, auditability, and git safety

### Goals

1. enforce encrypted secret storage and rotation policy
2. verify webhook authenticity and API auth posture
3. ensure agent-triggered shipping actions stay policy-compliant

### Pain Points

1. fear of secret leakage from logs/transcripts
2. uncertainty about automated commit/push behavior
3. weak incident response practices in typical AI tooling

### Success Signals

- visible security posture in settings and run logs
- documented runbooks for compromise/spoof attempts
- policy failures are explicit and actionable

### Core Routes Used

- `/settings/security`
- `/settings/api`
- `/projects/:id/runs/:run_id`

## Anti-Persona (Out of Scope)

### Multi-Tenant Admin

- needs teams, orgs, RBAC, and tenant isolation
- expects enterprise multi-user IAM workflows
- explicitly out of scope for current JidoCode direction
