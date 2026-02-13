# 04 — User Stories

## Epic A: Onboarding and Owner Bootstrap

### US-A1

As an OSS maintainer, I want first-run setup to guide me through required configuration so that I can reach a runnable state quickly.

Acceptance criteria:

1. incomplete setup redirects to `/setup`
2. step progress persists between sessions
3. completion requires successful validation of mandatory dependencies

### US-A2

As an OSS maintainer, I want to bootstrap my owner account during onboarding so that access is secured under single-user policy.

Acceptance criteria:

1. owner account creation/confirmation occurs in onboarding
2. production mode disables open registration by default
3. owner can sign in immediately after setup completion
4. no multi-tenant controls are exposed in onboarding

### US-A3

As an OSS maintainer, I want provider credentials validated during setup so that workflows fail less at runtime.

Acceptance criteria:

1. at least one LLM provider must validate
2. validation failures provide actionable remediation
3. secrets are never rendered in plaintext

## Epic B: Cross-Project Workbench (MVP Critical)

### US-B1

As an OSS maintainer, I want a single view of all projects, open issues, and open PRs so that I can prioritize maintenance work quickly.

Acceptance criteria:

1. `/workbench` lists all imported repos
2. each repo row includes issue and PR summaries
3. each issue/PR row links to source GitHub URL and local project context

### US-B2

As an OSS maintainer, I want to launch fix/triage jobs directly from issues and PRs in the workbench so that I can reduce manual orchestration.

Acceptance criteria:

1. workbench provides quick actions to start relevant agent workflows
2. kickoff creates a tracked workflow run
3. kickoff success/failure status is shown immediately

### US-B3

As an OSS maintainer, I want filtering and sorting in the workbench so that I can focus on urgent or stale maintenance items.

Acceptance criteria:

1. filters by project, issue/PR state, and freshness exist
2. sorting by backlog and recent activity exists
3. filter state is preserved while navigating to run detail and back

## Epic C: Project and Integration Setup

### US-C1

As an OSS maintainer, I want to connect GitHub App credentials so that JidoCode can import repos and process webhooks.

Acceptance criteria:

1. GitHub credentials can be validated from setup/settings
2. webhook signature path can be tested
3. integration status is visible in settings

### US-C2

As an OSS maintainer, I want to import my first repository during onboarding so that I can run a workflow immediately.

Acceptance criteria:

1. accessible repositories are listed
2. import initializes project metadata and workspace baseline
3. import failures preserve clear error context

## Epic D: Workflow Execution and Approvals

### US-D1

As an OSS maintainer, I want to launch an implement-task or fix workflow from workbench/project views so that I can automate maintenance work.

Acceptance criteria:

1. workflow can be started from `/workbench` and `/projects/:id`
2. run detail route streams timeline and logs
3. run status transitions are persisted and visible

### US-D2

As an OSS maintainer, I want approval gates before shipping so that automated code changes remain controlled.

Acceptance criteria:

1. run enters `awaiting_approval` before ship step when configured
2. approval context includes diff and test summary
3. approve/reject actions are recorded with audit metadata

### US-D3

As an OSS maintainer, I want failed runs to show retry-safe guidance so that I can recover quickly.

Acceptance criteria:

1. failure reason is typed and user-visible
2. retry options are available where policy allows
3. partial artifacts remain accessible

## Epic E: Git and PR Shipping

### US-E1

As an OSS maintainer, I want branch/commit/push/PR automation so that approved runs ship with minimal manual effort.

Acceptance criteria:

1. successful approved runs can create PRs automatically
2. PR metadata is attached to workflow artifacts
3. no-change runs are clearly identified

### US-E2

As an OSS maintainer, I want strict git safety checks so that unsafe commits and pushes are blocked.

Acceptance criteria:

1. secret scan check is mandatory before shipping
2. branch collision handling is deterministic
3. policy violations block shipping and show remediation

## Epic F: Issue Bot MVP

### US-F1

As an OSS maintainer, I want issue webhooks to trigger triage workflows so that new issues are processed consistently.

Acceptance criteria:

1. `issues.opened` and `issues.edited` events trigger configured flows
2. signature verification and idempotency checks are enforced
3. trigger outcomes are visible in dashboard/workbench/agents views

### US-F2

As an OSS maintainer, I want per-project Issue Bot policy controls so that I can tune automation risk.

Acceptance criteria:

1. Issue Bot can be enabled/disabled per project
2. approval-required vs auto-post policy is configurable
3. current policy is visible in `/agents`

### US-F3

As an OSS maintainer, I want triage outputs and drafted responses persisted so that I can audit and improve automation quality.

Acceptance criteria:

1. triage classification and research artifacts are stored
2. proposed response is available for review
3. posted response URL is stored when auto-post or approval path completes

## Epic G: Security and Secret Operations

### US-G1

As a single-user operator, I want operational secrets encrypted at rest so that DB compromise risk is reduced.

Acceptance criteria:

1. operational secret fields are encrypted in persistence model
2. plaintext secret storage is disallowed in product contracts
3. secret source and rotation metadata are tracked

### US-G2

As a single-user operator, I want secret rotation and token revocation runbooks so that incidents can be handled quickly.

Acceptance criteria:

1. `/settings/security` links to operational runbooks
2. rotation/revoke actions have documented expected outcomes
3. audit records include actor and timestamp metadata

### US-G3

As a single-user operator, I want redaction applied across logs and artifacts so that sensitive values do not leak.

Acceptance criteria:

1. redaction policy covers logger, PubSub, artifact persistence, and prompt payloads
2. masked outputs are visible in UI instead of raw secrets
3. redaction failures are surfaced as high-priority errors

## Epic H: API and TypeScript RPC

### US-H1

As an integration developer for an OSS maintainer workflow, I want to validate action payloads before execution so that automation failures are reduced.

Acceptance criteria:

1. `POST /rpc/validate` supports product action inventory
2. validation errors are typed and actionable
3. auth mode requirements are documented per action policy

### US-H2

As an integration developer for an OSS maintainer workflow, I want typed action execution so that client code remains stable and safe.

Acceptance criteria:

1. `POST /rpc/run` executes product-domain public actions
2. generated `assets/js/ash_rpc.ts` reflects current action inventory
3. contract version mismatch has explicit migration messaging

### US-H3

As an OSS maintainer, I want API inventory visibility in UI so that I can trust external automation clients.

Acceptance criteria:

1. `/settings/api` shows RPC endpoint and action inventory status
2. current action inventory version is visible
3. missing coverage is surfaced as a warning condition

## Epic I: Observability and Operations

### US-I1

As an OSS maintainer, I want live run visibility so that I can intervene before failures cascade.

Acceptance criteria:

1. run detail shows live step transitions and output stream
2. dashboard shows recent runs and state summary
3. workbench shows recent run outcomes next to issue/PR context

### US-I2

As an OSS maintainer, I want consistent failure context so that post-mortems are fast and reliable.

Acceptance criteria:

1. each failed run includes last successful step, error type, and remediation hint
2. policy failure details are attached to run artifacts
3. run history remains queryable for trend review

## Story Prioritization

### MVP Must-Have

- US-A1, US-A2, US-A3
- US-B1, US-B2, US-B3
- US-C1, US-C2
- US-D1, US-D2, US-D3
- US-E1, US-E2
- US-F1, US-F2, US-F3
- US-G1, US-G2, US-G3
- US-H1, US-H2
- US-I1

### MVP Should-Have

- US-H3
- US-I2

### Phase 2+

- expanded support-agent stories beyond Issue Bot
- visual workflow authoring UX stories
- desktop (Tauri) setup stories
