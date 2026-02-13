# 01 — Onboarding and Owner Bootstrap Stories

Atomic MVP stories for first-run setup, owner bootstrap, and initial project readiness.

## Story Inventory

### ST-ONB-001 — Redirect incomplete instances to setup

#### Story ID
`ST-ONB-001`

#### Title
Redirect incomplete instances to setup

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/`

#### Requirement Links
R2

#### Source Spec Links
specs/11_onboarding_flow.md, specs/ux/03_routes_and_experience_flows.md

#### Dependencies
none

#### Story
As an OSS maintainer, I want incomplete setup state to redirect to setup so that required bootstrap steps cannot be skipped.

#### Acceptance Criteria
1. Navigating to `/` with `onboarding_completed=false` always redirects to `/setup`.
2. The redirect preserves the current onboarding step from `SystemConfig` so resume behavior is deterministic.
3. If `SystemConfig` cannot be loaded, the app still routes to `/setup` with actionable diagnostics instead of exposing protected routes.

#### Verification Scenarios
```gherkin
Scenario: ST-ONB-001 happy path
  Given prerequisites for "Redirect incomplete instances to setup" are satisfied
  When the actor executes the flow through "/"
  Then The redirect preserves the current onboarding step from `SystemConfig` so resume behavior is deterministic.

Scenario: ST-ONB-001 failure or edge path
  Given a blocking precondition exists for "Redirect incomplete instances to setup"
  When the actor executes the flow through "/"
  Then If `SystemConfig` cannot be loaded, the app still routes to `/setup` with actionable diagnostics instead of exposing protected routes.
```

#### Evidence of Done
- Setup UI and logs show redirect reason and resolved onboarding step.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-ONB-002 — Persist onboarding step progression and resume state

#### Story ID
`ST-ONB-002`

#### Title
Persist onboarding step progression and resume state

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/setup`

#### Requirement Links
R2

#### Source Spec Links
specs/11_onboarding_flow.md, specs/20_ash_domain_model.md

#### Dependencies
ST-ONB-001

#### Story
As an OSS maintainer, I want onboarding step state to persist so that interrupted setup can resume without data loss.

#### Acceptance Criteria
1. Each successful wizard step writes `onboarding_step` updates to `SystemConfig`.
2. Re-opening `/setup` resumes at the last incomplete step with prior validated state intact.
3. If a step save fails, the UI keeps the user on the same step and reports a retry-safe error.

#### Verification Scenarios
```gherkin
Scenario: ST-ONB-002 happy path
  Given prerequisites for "Persist onboarding step progression and resume state" are satisfied
  When the actor executes the flow through "/setup"
  Then Re-opening `/setup` resumes at the last incomplete step with prior validated state intact.

Scenario: ST-ONB-002 failure or edge path
  Given a blocking precondition exists for "Persist onboarding step progression and resume state"
  When the actor executes the flow through "/setup"
  Then If a step save fails, the UI keeps the user on the same step and reports a retry-safe error.
```

#### Evidence of Done
- `SystemConfig.onboarding_step` matches observed wizard progression across sessions.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-ONB-003 — Validate system prerequisites before owner bootstrap

#### Story ID
`ST-ONB-003`

#### Title
Validate system prerequisites before owner bootstrap

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/setup`

#### Requirement Links
R2, R11

#### Source Spec Links
specs/11_onboarding_flow.md, specs/61_configuration_and_deployment.md

#### Dependencies
ST-ONB-001

#### Story
As an OSS maintainer, I want startup checks for database and runtime configuration so that setup failures surface early.

#### Acceptance Criteria
1. Step 1 validates database connectivity and required runtime configuration before step advancement.
2. Validation failures provide actionable remediation text tied to the missing or failing prerequisite.
3. If prerequisite checks timeout, onboarding remains blocked and no downstream setup data is persisted.

#### Verification Scenarios
```gherkin
Scenario: ST-ONB-003 happy path
  Given prerequisites for "Validate system prerequisites before owner bootstrap" are satisfied
  When the actor executes the flow through "/setup"
  Then Validation failures provide actionable remediation text tied to the missing or failing prerequisite.

Scenario: ST-ONB-003 failure or edge path
  Given a blocking precondition exists for "Validate system prerequisites before owner bootstrap"
  When the actor executes the flow through "/setup"
  Then If prerequisite checks timeout, onboarding remains blocked and no downstream setup data is persisted.
```

#### Evidence of Done
- Prerequisite check results are visible in setup with timestamped status.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-ONB-004 — Bootstrap exactly one owner account

#### Story ID
`ST-ONB-004`

#### Title
Bootstrap exactly one owner account

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/setup`

#### Requirement Links
R1, R2

#### Source Spec Links
specs/11_onboarding_flow.md, specs/60_security_and_auth.md

#### Dependencies
ST-ONB-002

#### Story
As an OSS maintainer, I want onboarding to create or confirm one owner account so that instance control stays single-user.

#### Acceptance Criteria
1. Step 2 allows owner creation when no owner exists and owner confirmation when one exists.
2. After successful bootstrap, owner session access to protected routes is immediately available.
3. If an additional owner creation attempt is made, the action is blocked with a single-user policy error.

#### Verification Scenarios
```gherkin
Scenario: ST-ONB-004 happy path
  Given prerequisites for "Bootstrap exactly one owner account" are satisfied
  When the actor executes the flow through "/setup"
  Then After successful bootstrap, owner session access to protected routes is immediately available.

Scenario: ST-ONB-004 failure or edge path
  Given a blocking precondition exists for "Bootstrap exactly one owner account"
  When the actor executes the flow through "/setup"
  Then If an additional owner creation attempt is made, the action is blocked with a single-user policy error.
```

#### Evidence of Done
- Accounts data shows one active owner and setup marks owner bootstrap complete.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-ONB-005 — Disable open registration in production mode

#### Story ID
`ST-ONB-005`

#### Title
Disable open registration in production mode

#### Persona
Security-Conscious Engineering Lead (P3)

#### Priority
MVP Must

#### Primary Route/API
`/setup`

#### Requirement Links
R1, R2

#### Source Spec Links
specs/11_onboarding_flow.md, specs/03_decisions_and_invariants.md

#### Dependencies
ST-ONB-004

#### Story
As a security-conscious engineering lead, I want open registration disabled in production so that unauthorized account creation is prevented.

#### Acceptance Criteria
1. Production onboarding marks registration actions disabled after owner bootstrap completes.
2. Owner login remains functional while registration endpoints reject new user creation attempts.
3. If runtime mode is production and registration is requested, the request fails with a typed authorization error.

#### Verification Scenarios
```gherkin
Scenario: ST-ONB-005 happy path
  Given prerequisites for "Disable open registration in production mode" are satisfied
  When the actor executes the flow through "/setup"
  Then Owner login remains functional while registration endpoints reject new user creation attempts.

Scenario: ST-ONB-005 failure or edge path
  Given a blocking precondition exists for "Disable open registration in production mode"
  When the actor executes the flow through "/setup"
  Then If runtime mode is production and registration is requested, the request fails with a typed authorization error.
```

#### Evidence of Done
- Auth settings and behavior confirm production registration lockout.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-ONB-006 — Verify at least one LLM provider credential

#### Story ID
`ST-ONB-006`

#### Title
Verify at least one LLM provider credential

#### Persona
Solo Developer or Small Team Lead (P2)

#### Priority
MVP Must

#### Primary Route/API
`/setup`

#### Requirement Links
R2, R6

#### Source Spec Links
specs/11_onboarding_flow.md, specs/02_requirements_and_scope.md

#### Dependencies
ST-ONB-003

#### Story
As a solo developer, I want at least one provider credential verified during setup so that workflows can run immediately after onboarding.

#### Acceptance Criteria
1. Step 3 requires one provider verification status of `active` before completion is allowed.
2. Provider verification results include clear status transitions and remediation guidance for invalid credentials.
3. If all provider checks fail, onboarding cannot proceed to GitHub setup and no false success state is recorded.

#### Verification Scenarios
```gherkin
Scenario: ST-ONB-006 happy path
  Given prerequisites for "Verify at least one LLM provider credential" are satisfied
  When the actor executes the flow through "/setup"
  Then Provider verification results include clear status transitions and remediation guidance for invalid credentials.

Scenario: ST-ONB-006 failure or edge path
  Given a blocking precondition exists for "Verify at least one LLM provider credential"
  When the actor executes the flow through "/setup"
  Then If all provider checks fail, onboarding cannot proceed to GitHub setup and no false success state is recorded.
```

#### Evidence of Done
- `ProviderCredential.status` and `verified_at` reflect successful verification.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-ONB-007 — Validate GitHub integration credentials during setup

#### Story ID
`ST-ONB-007`

#### Title
Validate GitHub integration credentials during setup

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/setup`

#### Requirement Links
R2, R3

#### Source Spec Links
specs/11_onboarding_flow.md, specs/50_github_integration.md

#### Dependencies
ST-ONB-006

#### Story
As an OSS maintainer, I want GitHub credentials validated in setup so that repo import and webhook flows are reliable.

#### Acceptance Criteria
1. Step 4 validates either GitHub App credentials or PAT fallback before step completion.
2. Credential validation confirms repository access capability for the owner context.
3. If both credential paths fail validation, setup stays blocked with typed integration errors.

#### Verification Scenarios
```gherkin
Scenario: ST-ONB-007 happy path
  Given prerequisites for "Validate GitHub integration credentials during setup" are satisfied
  When the actor executes the flow through "/setup"
  Then Credential validation confirms repository access capability for the owner context.

Scenario: ST-ONB-007 failure or edge path
  Given a blocking precondition exists for "Validate GitHub integration credentials during setup"
  When the actor executes the flow through "/setup"
  Then If both credential paths fail validation, setup stays blocked with typed integration errors.
```

#### Evidence of Done
- Setup displays integration status with last validation timestamp.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-ONB-008 — Run webhook simulation before Issue Bot enablement

#### Story ID
`ST-ONB-008`

#### Title
Run webhook simulation before Issue Bot enablement

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/setup`

#### Requirement Links
R2, R3, R8

#### Source Spec Links
specs/11_onboarding_flow.md, specs/50_github_integration.md

#### Dependencies
ST-ONB-007

#### Story
As an OSS maintainer, I want webhook simulation checks during setup so that Issue Bot policies are not enabled on broken webhook paths.

#### Acceptance Criteria
1. Step 6 executes a webhook simulation and records success before enabling Issue Bot defaults.
2. Simulation output indicates signature and routing readiness for configured events.
3. If simulation fails, Issue Bot enablement is blocked and the failure reason is retained for retry.

#### Verification Scenarios
```gherkin
Scenario: ST-ONB-008 happy path
  Given prerequisites for "Run webhook simulation before Issue Bot enablement" are satisfied
  When the actor executes the flow through "/setup"
  Then Simulation output indicates signature and routing readiness for configured events.

Scenario: ST-ONB-008 failure or edge path
  Given a blocking precondition exists for "Run webhook simulation before Issue Bot enablement"
  When the actor executes the flow through "/setup"
  Then If simulation fails, Issue Bot enablement is blocked and the failure reason is retained for retry.
```

#### Evidence of Done
- Issue Bot readiness status is shown with last simulation outcome.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-ONB-009 — Select and validate default execution environment

#### Story ID
`ST-ONB-009`

#### Title
Select and validate default execution environment

#### Persona
Solo Developer or Small Team Lead (P2)

#### Priority
MVP Must

#### Primary Route/API
`/setup`

#### Requirement Links
R4, R11

#### Source Spec Links
specs/11_onboarding_flow.md, specs/40_project_environments.md

#### Dependencies
ST-ONB-003

#### Story
As a solo developer, I want to select cloud or local execution defaults during setup so that runtime mode matches deployment context.

#### Acceptance Criteria
1. Step 5 persists environment defaults in `SystemConfig` and validates required tools for the selected mode.
2. Local mode requires a valid workspace root and cloud mode enforces sprite-default behavior.
3. If selected mode validation fails, onboarding remains on environment step without mutating defaults.

#### Verification Scenarios
```gherkin
Scenario: ST-ONB-009 happy path
  Given prerequisites for "Select and validate default execution environment" are satisfied
  When the actor executes the flow through "/setup"
  Then Local mode requires a valid workspace root and cloud mode enforces sprite-default behavior.

Scenario: ST-ONB-009 failure or edge path
  Given a blocking precondition exists for "Select and validate default execution environment"
  When the actor executes the flow through "/setup"
  Then If selected mode validation fails, onboarding remains on environment step without mutating defaults.
```

#### Evidence of Done
- `SystemConfig.default_environment` and workspace validation results match selected mode.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-ONB-010 — Import first project and finalize onboarding

#### Story ID
`ST-ONB-010`

#### Title
Import first project and finalize onboarding

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/setup`

#### Requirement Links
R2, R4, R13

#### Source Spec Links
specs/11_onboarding_flow.md, specs/10_web_ui_and_routes.md

#### Dependencies
ST-ONB-007, ST-ONB-009

#### Story
As an OSS maintainer, I want first project import and onboarding completion to happen in one guided flow so that I can start workflows immediately.

#### Acceptance Criteria
1. Step 7 imports a selected repository and initializes project baseline metadata.
2. Step 8 sets `onboarding_completed=true` and routes the owner to `/dashboard` with next actions.
3. If import fails, onboarding completion is blocked and no completion flag is persisted.

#### Verification Scenarios
```gherkin
Scenario: ST-ONB-010 happy path
  Given prerequisites for "Import first project and finalize onboarding" are satisfied
  When the actor executes the flow through "/setup"
  Then Step 8 sets `onboarding_completed=true` and routes the owner to `/dashboard` with next actions.

Scenario: ST-ONB-010 failure or edge path
  Given a blocking precondition exists for "Import first project and finalize onboarding"
  When the actor executes the flow through "/setup"
  Then If import fails, onboarding completion is blocked and no completion flag is persisted.
```

#### Evidence of Done
- Project record exists with ready baseline and dashboard access is granted post-completion.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

## Story Count

- 10 stories
