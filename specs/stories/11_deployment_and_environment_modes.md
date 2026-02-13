# 11 — Deployment and Environment Mode Stories

Atomic MVP stories for cloud-first deployment, local fallback, and runtime configuration safety.

## Story Inventory

### ST-DEP-001 — Run cloud VM deployment checklist to ready state

#### Story ID
`ST-DEP-001`

#### Title
Run cloud VM deployment checklist to ready state

#### Persona
Solo Developer or Small Team Lead (P2)

#### Priority
MVP Must

#### Primary Route/API
`Cloud VM deployment flow`

#### Requirement Links
R11

#### Source Spec Links
specs/61_configuration_and_deployment.md, specs/README.md

#### Dependencies
none

#### Story
As a solo developer, I want a cloud deployment checklist so that production setup reaches a known ready state consistently.

#### Acceptance Criteria
1. Deployment checklist covers provisioning secrets migrations HTTPS and webhook endpoint configuration.
2. Checklist completion criteria require passing health and readiness probes.
3. If a checklist step fails, deployment is marked incomplete with step-specific remediation guidance.

#### Verification Scenarios
```gherkin
Scenario: ST-DEP-001 happy path
  Given prerequisites for "Run cloud VM deployment checklist to ready state" are satisfied
  When the actor executes the flow through "Cloud VM deployment flow"
  Then Checklist completion criteria require passing health and readiness probes.

Scenario: ST-DEP-001 failure or edge path
  Given a blocking precondition exists for "Run cloud VM deployment checklist to ready state"
  When the actor executes the flow through "Cloud VM deployment flow"
  Then If a checklist step fails, deployment is marked incomplete with step-specific remediation guidance.
```

#### Evidence of Done
- Operational records show completed checklist with timestamped step outcomes.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-DEP-002 — Enforce localhost-safe defaults for local mode

#### Story ID
`ST-DEP-002`

#### Title
Enforce localhost-safe defaults for local mode

#### Persona
Solo Developer or Small Team Lead (P2)

#### Priority
MVP Must

#### Primary Route/API
`Local dev mode`

#### Requirement Links
R11, R10

#### Source Spec Links
specs/61_configuration_and_deployment.md, specs/60_security_and_auth.md

#### Dependencies
none

#### Story
As a solo developer, I want local mode to default to localhost so that accidental external exposure is minimized.

#### Acceptance Criteria
1. Local development binds to localhost by default and requires explicit opt-in for external exposure.
2. External exposure attempts surface clear warning messaging before startup confirmation.
3. If unsafe host configuration is detected, startup blocks or warns according to policy.

#### Verification Scenarios
```gherkin
Scenario: ST-DEP-002 happy path
  Given prerequisites for "Enforce localhost-safe defaults for local mode" are satisfied
  When the actor executes the flow through "Local dev mode"
  Then External exposure attempts surface clear warning messaging before startup confirmation.

Scenario: ST-DEP-002 failure or edge path
  Given a blocking precondition exists for "Enforce localhost-safe defaults for local mode"
  When the actor executes the flow through "Local dev mode"
  Then If unsafe host configuration is detected, startup blocks or warns according to policy.
```

#### Evidence of Done
- Runtime config output confirms active bind host and exposure mode.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-DEP-003 — Validate required environment variables at startup

#### Story ID
`ST-DEP-003`

#### Title
Validate required environment variables at startup

#### Persona
Solo Developer or Small Team Lead (P2)

#### Priority
MVP Must

#### Primary Route/API
`Application startup`

#### Requirement Links
R11, R10

#### Source Spec Links
specs/61_configuration_and_deployment.md, specs/11_onboarding_flow.md

#### Dependencies
none

#### Story
As a solo developer, I want startup validation for required environment variables so that runtime failures are caught early.

#### Acceptance Criteria
1. Startup checks required variables like SECRET_KEY_BASE DATABASE_URL PHX_HOST and TOKEN_SIGNING_SECRET.
2. Missing required values produce actionable failure output and prevent partial startup.
3. If variable format is invalid, startup fails with typed configuration diagnostics.

#### Verification Scenarios
```gherkin
Scenario: ST-DEP-003 happy path
  Given prerequisites for "Validate required environment variables at startup" are satisfied
  When the actor executes the flow through "Application startup"
  Then Missing required values produce actionable failure output and prevent partial startup.

Scenario: ST-DEP-003 failure or edge path
  Given a blocking precondition exists for "Validate required environment variables at startup"
  When the actor executes the flow through "Application startup"
  Then If variable format is invalid, startup fails with typed configuration diagnostics.
```

#### Evidence of Done
- Startup diagnostics list each required variable validation outcome.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-DEP-004 — Validate provider and integration env inputs during setup

#### Story ID
`ST-DEP-004`

#### Title
Validate provider and integration env inputs during setup

#### Persona
Solo Developer or Small Team Lead (P2)

#### Priority
MVP Must

#### Primary Route/API
`/setup`

#### Requirement Links
R11, R3, R6

#### Source Spec Links
specs/61_configuration_and_deployment.md, specs/11_onboarding_flow.md

#### Dependencies
ST-ONB-003

#### Story
As a solo developer, I want provider and integration env checks in setup so that credential wiring issues are found before workflow execution.

#### Acceptance Criteria
1. Setup detects provider and integration environment variables and reports availability state.
2. Detected variables can satisfy credential prerequisites where policy permits env-root sourcing.
3. If required integration values are missing, setup blocks dependent steps and shows remediation.

#### Verification Scenarios
```gherkin
Scenario: ST-DEP-004 happy path
  Given prerequisites for "Validate provider and integration env inputs during setup" are satisfied
  When the actor executes the flow through "/setup"
  Then Detected variables can satisfy credential prerequisites where policy permits env-root sourcing.

Scenario: ST-DEP-004 failure or edge path
  Given a blocking precondition exists for "Validate provider and integration env inputs during setup"
  When the actor executes the flow through "/setup"
  Then If required integration values are missing, setup blocks dependent steps and shows remediation.
```

#### Evidence of Done
- Setup diagnostics show per-variable readiness without exposing secret values.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-DEP-005 — Persist deployment mode and default environment selection

#### Story ID
`ST-DEP-005`

#### Title
Persist deployment mode and default environment selection

#### Persona
Solo Developer or Small Team Lead (P2)

#### Priority
MVP Must

#### Primary Route/API
`/setup`

#### Requirement Links
R4, R11

#### Source Spec Links
specs/20_ash_domain_model.md, specs/11_onboarding_flow.md

#### Dependencies
ST-ONB-009

#### Story
As a solo developer, I want deployment mode and environment defaults persisted so that runtime behavior is stable after restarts.

#### Acceptance Criteria
1. SystemConfig persists deployment mode cloud_vm or local and default environment sprite or local.
2. Persisted mode values are loaded on restart and used to initialize workspace behavior.
3. If mode persistence fails, setup remains incomplete and no ambiguous defaults are applied.

#### Verification Scenarios
```gherkin
Scenario: ST-DEP-005 happy path
  Given prerequisites for "Persist deployment mode and default environment selection" are satisfied
  When the actor executes the flow through "/setup"
  Then Persisted mode values are loaded on restart and used to initialize workspace behavior.

Scenario: ST-DEP-005 failure or edge path
  Given a blocking precondition exists for "Persist deployment mode and default environment selection"
  When the actor executes the flow through "/setup"
  Then If mode persistence fails, setup remains incomplete and no ambiguous defaults are applied.
```

#### Evidence of Done
- System configuration endpoints show consistent persisted mode values.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-DEP-006 — Expose readiness probe including database and workflow dependencies

#### Story ID
`ST-DEP-006`

#### Title
Expose readiness probe including database and workflow dependencies

#### Persona
Platform Operator

#### Priority
MVP Must

#### Primary Route/API
`/status`

#### Requirement Links
R11, R5

#### Source Spec Links
specs/61_configuration_and_deployment.md, specs/30_workflow_system_overview.md

#### Dependencies
none

#### Story
As a platform operator, I want readiness probes to include critical dependencies so that deployment health reflects workflow start capability.

#### Acceptance Criteria
1. Readiness checks include database connectivity and key services required for run startup.
2. Probe response distinguishes healthy degraded and failed dependency states.
3. If a critical dependency is unavailable, readiness reports non-ready while liveness can remain up.

#### Verification Scenarios
```gherkin
Scenario: ST-DEP-006 happy path
  Given prerequisites for "Expose readiness probe including database and workflow dependencies" are satisfied
  When the actor executes the flow through "/status"
  Then Probe response distinguishes healthy degraded and failed dependency states.

Scenario: ST-DEP-006 failure or edge path
  Given a blocking precondition exists for "Expose readiness probe including database and workflow dependencies"
  When the actor executes the flow through "/status"
  Then If a critical dependency is unavailable, readiness reports non-ready while liveness can remain up.
```

#### Evidence of Done
- Status endpoint output shows dependency-level readiness details.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-DEP-007 — Support webhook endpoint configuration across cloud and local setups

#### Story ID
`ST-DEP-007`

#### Title
Support webhook endpoint configuration across cloud and local setups

#### Persona
Solo Developer or Small Team Lead (P2)

#### Priority
MVP Must

#### Primary Route/API
`POST /api/github/webhooks`

#### Requirement Links
R11, R3

#### Source Spec Links
specs/61_configuration_and_deployment.md, specs/50_github_integration.md

#### Dependencies
ST-GH-006

#### Story
As a solo developer, I want webhook endpoint configuration guidance per deployment mode so that GitHub events reach the service reliably.

#### Acceptance Criteria
1. Cloud deployment uses direct HTTPS webhook endpoint configuration and validation steps.
2. Local mode supports tunnel-based webhook delivery with explicit setup guidance.
3. If webhook endpoint is unreachable, setup reports delivery failure and remediation actions.

#### Verification Scenarios
```gherkin
Scenario: ST-DEP-007 happy path
  Given prerequisites for "Support webhook endpoint configuration across cloud and local setups" are satisfied
  When the actor executes the flow through "POST /api/github/webhooks"
  Then Local mode supports tunnel-based webhook delivery with explicit setup guidance.

Scenario: ST-DEP-007 failure or edge path
  Given a blocking precondition exists for "Support webhook endpoint configuration across cloud and local setups"
  When the actor executes the flow through "POST /api/github/webhooks"
  Then If webhook endpoint is unreachable, setup reports delivery failure and remediation actions.
```

#### Evidence of Done
- Webhook diagnostics confirm reachable endpoint and signature verification readiness.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-DEP-008 — Enforce one active shipping run per project by default

#### Story ID
`ST-DEP-008`

#### Title
Enforce one active shipping run per project by default

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`Workflow scheduling and queueing`

#### Requirement Links
R5, R7, R11

#### Source Spec Links
specs/40_project_environments.md, specs/30_workflow_system_overview.md

#### Dependencies
ST-WF-001

#### Story
As an OSS maintainer, I want default single active shipping run policy so that concurrent git side effects do not conflict.

#### Acceptance Criteria
1. Scheduler allows one active shipping run per project unless explicit isolation policy is configured.
2. Additional shipping runs are queued or isolated according to concurrency policy settings.
3. If policy evaluation fails, new shipping runs are blocked rather than started unsafely.

#### Verification Scenarios
```gherkin
Scenario: ST-DEP-008 happy path
  Given prerequisites for "Enforce one active shipping run per project by default" are satisfied
  When the actor executes the flow through "Workflow scheduling and queueing"
  Then Additional shipping runs are queued or isolated according to concurrency policy settings.

Scenario: ST-DEP-008 failure or edge path
  Given a blocking precondition exists for "Enforce one active shipping run per project by default"
  When the actor executes the flow through "Workflow scheduling and queueing"
  Then If policy evaluation fails, new shipping runs are blocked rather than started unsafely.
```

#### Evidence of Done
- Run queue and scheduler state show policy-enforced execution ordering.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

## Story Count

- 8 stories
