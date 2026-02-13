# 04 — GitHub Integration and Repo Import Stories

Atomic MVP stories for GitHub auth paths, webhook security, and repository import lifecycle.

## Story Inventory

### ST-GH-001 — Validate GitHub App credentials and installation access

#### Story ID
`ST-GH-001`

#### Title
Validate GitHub App credentials and installation access

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/setup`

#### Requirement Links
R3

#### Source Spec Links
specs/50_github_integration.md, specs/11_onboarding_flow.md

#### Dependencies
ST-ONB-007

#### Story
As an OSS maintainer, I want GitHub App credentials validated so that import and webhook features are dependable.

#### Acceptance Criteria
1. Validation confirms App credentials and installation access for expected repositories.
2. Successful validation records integration health metadata and readiness status.
3. If credentials or installation are invalid, setup remains blocked with typed integration errors.

#### Verification Scenarios
```gherkin
Scenario: ST-GH-001 happy path
  Given prerequisites for "Validate GitHub App credentials and installation access" are satisfied
  When the actor executes the flow through "/setup"
  Then Successful validation records integration health metadata and readiness status.

Scenario: ST-GH-001 failure or edge path
  Given a blocking precondition exists for "Validate GitHub App credentials and installation access"
  When the actor executes the flow through "/setup"
  Then If credentials or installation are invalid, setup remains blocked with typed integration errors.
```

#### Evidence of Done
- Integration status reflects GitHub App readiness with last check time.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-GH-002 — Support PAT fallback for simple GitHub setup

#### Story ID
`ST-GH-002`

#### Title
Support PAT fallback for simple GitHub setup

#### Persona
Solo Developer or Small Team Lead (P2)

#### Priority
MVP Should

#### Primary Route/API
`/setup`

#### Requirement Links
R3

#### Source Spec Links
specs/50_github_integration.md, specs/11_onboarding_flow.md

#### Dependencies
none

#### Story
As a solo developer, I want PAT fallback support so that setup can proceed when GitHub App is unavailable.

#### Acceptance Criteria
1. PAT credentials can be validated and used when App path is intentionally not configured.
2. PAT mode clearly indicates reduced granularity relative to App mode in settings feedback.
3. If PAT validation fails, setup reports failure and does not mark integration as ready.

#### Verification Scenarios
```gherkin
Scenario: ST-GH-002 happy path
  Given prerequisites for "Support PAT fallback for simple GitHub setup" are satisfied
  When the actor executes the flow through "/setup"
  Then PAT mode clearly indicates reduced granularity relative to App mode in settings feedback.

Scenario: ST-GH-002 failure or edge path
  Given a blocking precondition exists for "Support PAT fallback for simple GitHub setup"
  When the actor executes the flow through "/setup"
  Then If PAT validation fails, setup reports failure and does not mark integration as ready.
```

#### Evidence of Done
- Settings show active GitHub auth mode and validation state.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-GH-003 — List accessible repositories for import selection

#### Story ID
`ST-GH-003`

#### Title
List accessible repositories for import selection

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/setup`

#### Requirement Links
R3, R4

#### Source Spec Links
specs/50_github_integration.md, specs/11_onboarding_flow.md

#### Dependencies
ST-GH-001

#### Story
As an OSS maintainer, I want accessible repositories listed in setup so that first import is straightforward.

#### Acceptance Criteria
1. Repository listing returns only repos accessible to configured GitHub credentials.
2. List results include stable identifiers needed for deterministic import selection.
3. If listing fails, setup surfaces typed GitHub fetch error and preserves prior step state.

#### Verification Scenarios
```gherkin
Scenario: ST-GH-003 happy path
  Given prerequisites for "List accessible repositories for import selection" are satisfied
  When the actor executes the flow through "/setup"
  Then List results include stable identifiers needed for deterministic import selection.

Scenario: ST-GH-003 failure or edge path
  Given a blocking precondition exists for "List accessible repositories for import selection"
  When the actor executes the flow through "/setup"
  Then If listing fails, setup surfaces typed GitHub fetch error and preserves prior step state.
```

#### Evidence of Done
- Import selector displays repository options with refresh behavior.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-GH-004 — Create project records from selected repository import

#### Story ID
`ST-GH-004`

#### Title
Create project records from selected repository import

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/setup`

#### Requirement Links
R4, R13

#### Source Spec Links
specs/50_github_integration.md, specs/20_ash_domain_model.md

#### Dependencies
ST-GH-003

#### Story
As an OSS maintainer, I want repository import to create project metadata so that workbench and workflows can target the project.

#### Acceptance Criteria
1. Import creates `Project` records with `github_full_name` and default branch metadata.
2. Duplicate import attempts do not create duplicate project records for the same repository.
3. If project creation fails, import reports typed persistence failure and no partial project state is exposed.

#### Verification Scenarios
```gherkin
Scenario: ST-GH-004 happy path
  Given prerequisites for "Create project records from selected repository import" are satisfied
  When the actor executes the flow through "/setup"
  Then Duplicate import attempts do not create duplicate project records for the same repository.

Scenario: ST-GH-004 failure or edge path
  Given a blocking precondition exists for "Create project records from selected repository import"
  When the actor executes the flow through "/setup"
  Then If project creation fails, import reports typed persistence failure and no partial project state is exposed.
```

#### Evidence of Done
- Project inventory includes imported repository with expected metadata.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-GH-005 — Provision clone and baseline sync during import

#### Story ID
`ST-GH-005`

#### Title
Provision clone and baseline sync during import

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/setup`

#### Requirement Links
R4

#### Source Spec Links
specs/50_github_integration.md, specs/40_project_environments.md

#### Dependencies
ST-GH-004

#### Story
As an OSS maintainer, I want imported repositories cloned and baseline synced so that first workflow runs do not start from stale workspace state.

#### Acceptance Criteria
1. Import provisions workspace and updates clone status through pending cloning ready states.
2. Baseline sync aligns workspace to configured default branch before run kickoff.
3. If clone or sync fails, project clone status becomes error with actionable retry instructions.

#### Verification Scenarios
```gherkin
Scenario: ST-GH-005 happy path
  Given prerequisites for "Provision clone and baseline sync during import" are satisfied
  When the actor executes the flow through "/setup"
  Then Baseline sync aligns workspace to configured default branch before run kickoff.

Scenario: ST-GH-005 failure or edge path
  Given a blocking precondition exists for "Provision clone and baseline sync during import"
  When the actor executes the flow through "/setup"
  Then If clone or sync fails, project clone status becomes error with actionable retry instructions.
```

#### Evidence of Done
- Project detail shows clone status transitions and last sync timestamp.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-GH-006 — Verify webhook signatures for inbound GitHub deliveries

#### Story ID
`ST-GH-006`

#### Title
Verify webhook signatures for inbound GitHub deliveries

#### Persona
Security-Conscious Engineering Lead (P3)

#### Priority
MVP Must

#### Primary Route/API
`POST /api/github/webhooks`

#### Requirement Links
R3, R8, R10

#### Source Spec Links
specs/50_github_integration.md, specs/60_security_and_auth.md

#### Dependencies
none

#### Story
As a security-conscious engineering lead, I want webhook signatures verified so that spoofed events are rejected.

#### Acceptance Criteria
1. Webhook processing enforces `X-Hub-Signature-256` verification before routing events.
2. Verified payloads proceed to idempotency and trigger mapping steps.
3. If signature verification fails, delivery is rejected and logged without workflow side effects.

#### Verification Scenarios
```gherkin
Scenario: ST-GH-006 happy path
  Given prerequisites for "Verify webhook signatures for inbound GitHub deliveries" are satisfied
  When the actor executes the flow through "POST /api/github/webhooks"
  Then Verified payloads proceed to idempotency and trigger mapping steps.

Scenario: ST-GH-006 failure or edge path
  Given a blocking precondition exists for "Verify webhook signatures for inbound GitHub deliveries"
  When the actor executes the flow through "POST /api/github/webhooks"
  Then If signature verification fails, delivery is rejected and logged without workflow side effects.
```

#### Evidence of Done
- Webhook logs show signature decision outcomes and associated delivery metadata.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-GH-007 — Enforce webhook idempotency by delivery ID

#### Story ID
`ST-GH-007`

#### Title
Enforce webhook idempotency by delivery ID

#### Persona
Security-Conscious Engineering Lead (P3)

#### Priority
MVP Must

#### Primary Route/API
`POST /api/github/webhooks`

#### Requirement Links
R3, R8, R10

#### Source Spec Links
specs/50_github_integration.md, specs/60_security_and_auth.md

#### Dependencies
ST-GH-006

#### Story
As a security-conscious engineering lead, I want delivery ID idempotency checks so that duplicate webhooks do not trigger duplicate runs.

#### Acceptance Criteria
1. Webhook deliveries persist a unique delivery identifier before trigger dispatch.
2. Duplicate deliveries are acknowledged safely without creating duplicate workflow runs.
3. If delivery ID cannot be persisted, processing fails closed and no trigger action occurs.

#### Verification Scenarios
```gherkin
Scenario: ST-GH-007 happy path
  Given prerequisites for "Enforce webhook idempotency by delivery ID" are satisfied
  When the actor executes the flow through "POST /api/github/webhooks"
  Then Duplicate deliveries are acknowledged safely without creating duplicate workflow runs.

Scenario: ST-GH-007 failure or edge path
  Given a blocking precondition exists for "Enforce webhook idempotency by delivery ID"
  When the actor executes the flow through "POST /api/github/webhooks"
  Then If delivery ID cannot be persisted, processing fails closed and no trigger action occurs.
```

#### Evidence of Done
- Delivery records show unique IDs and duplicate detection outcomes.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-GH-008 — Map issue events to Issue Bot trigger rules

#### Story ID
`ST-GH-008`

#### Title
Map issue events to Issue Bot trigger rules

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`POST /api/github/webhooks`

#### Requirement Links
R3, R8

#### Source Spec Links
specs/50_github_integration.md, specs/31_builtin_workflows.md

#### Dependencies
ST-GH-006, ST-BOT-001

#### Story
As an OSS maintainer, I want issue webhook events mapped to Issue Bot rules so that triage workflows run consistently.

#### Acceptance Criteria
1. `issues.opened` and `issues.edited` events map to configured Issue Bot workflow triggers.
2. Trigger dispatch includes project and policy context required for downstream run behavior.
3. If event mapping has no enabled project match, no run is created and a clear no-op reason is recorded.

#### Verification Scenarios
```gherkin
Scenario: ST-GH-008 happy path
  Given prerequisites for "Map issue events to Issue Bot trigger rules" are satisfied
  When the actor executes the flow through "POST /api/github/webhooks"
  Then Trigger dispatch includes project and policy context required for downstream run behavior.

Scenario: ST-GH-008 failure or edge path
  Given a blocking precondition exists for "Map issue events to Issue Bot trigger rules"
  When the actor executes the flow through "POST /api/github/webhooks"
  Then If event mapping has no enabled project match, no run is created and a clear no-op reason is recorded.
```

#### Evidence of Done
- Trigger audit entries show mapped event type and dispatch status.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-GH-009 — Sync installation events to repo availability metadata

#### Story ID
`ST-GH-009`

#### Title
Sync installation events to repo availability metadata

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Should

#### Primary Route/API
`POST /api/github/webhooks`

#### Requirement Links
R3, R4

#### Source Spec Links
specs/50_github_integration.md, specs/20_ash_domain_model.md

#### Dependencies
ST-GH-006

#### Story
As an OSS maintainer, I want installation events processed so that repository availability stays current.

#### Acceptance Criteria
1. `installation.*` webhook events update accessible repository and installation metadata state.
2. Repo availability changes become visible in project import and sync surfaces.
3. If installation sync fails, stale-state warning is surfaced with retry guidance.

#### Verification Scenarios
```gherkin
Scenario: ST-GH-009 happy path
  Given prerequisites for "Sync installation events to repo availability metadata" are satisfied
  When the actor executes the flow through "POST /api/github/webhooks"
  Then Repo availability changes become visible in project import and sync surfaces.

Scenario: ST-GH-009 failure or edge path
  Given a blocking precondition exists for "Sync installation events to repo availability metadata"
  When the actor executes the flow through "POST /api/github/webhooks"
  Then If installation sync fails, stale-state warning is surfaced with retry guidance.
```

#### Evidence of Done
- Installation sync logs show event handling outcome and affected repositories.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-GH-010 — Use Req with typed retry behavior for GitHub API calls

#### Story ID
`ST-GH-010`

#### Title
Use Req with typed retry behavior for GitHub API calls

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`GitHub HTTP integration layer`

#### Requirement Links
R3, R8

#### Source Spec Links
specs/50_github_integration.md, specs/02_requirements_and_scope.md

#### Dependencies
none

#### Story
As an OSS maintainer, I want GitHub API calls to use Req with explicit retry and timeout behavior so that integration failures are typed and recoverable.

#### Acceptance Criteria
1. GitHub client operations use Req with explicit timeout and retry configuration.
2. GitHub errors map to typed internal failure reasons used by workflows and UI.
3. If retries are exhausted, the final error preserves request intent and remediation guidance.

#### Verification Scenarios
```gherkin
Scenario: ST-GH-010 happy path
  Given prerequisites for "Use Req with typed retry behavior for GitHub API calls" are satisfied
  When the actor executes the flow through "GitHub HTTP integration layer"
  Then GitHub errors map to typed internal failure reasons used by workflows and UI.

Scenario: ST-GH-010 failure or edge path
  Given a blocking precondition exists for "Use Req with typed retry behavior for GitHub API calls"
  When the actor executes the flow through "GitHub HTTP integration layer"
  Then If retries are exhausted, the final error preserves request intent and remediation guidance.
```

#### Evidence of Done
- Error artifacts show typed reason mapping for failed GitHub operations.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

## Story Count

- 10 stories
