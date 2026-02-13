# 10 — RPC and TypeScript Client Stories

Atomic MVP stories for typed Ash RPC endpoints, auth modes, and generated TypeScript parity.

## Story Inventory

### ST-RPC-001 — Validate public action payloads through RPC validate endpoint

#### Story ID
`ST-RPC-001`

#### Title
Validate public action payloads through RPC validate endpoint

#### Persona
Integration Developer

#### Priority
MVP Must

#### Primary Route/API
`POST /rpc/validate`

#### Requirement Links
R12

#### Source Spec Links
specs/10_web_ui_and_routes.md, specs/32_agent_and_action_catalog.md

#### Dependencies
none

#### Story
As an integration developer, I want payload validation endpoint support so that bad action requests fail before execution.

#### Acceptance Criteria
1. `/rpc/validate` accepts product public action identifiers and input payloads.
2. Validation responses return typed success or structured error output without side effects.
3. If action name is unknown, endpoint returns typed contract mismatch error.

#### Verification Scenarios
```gherkin
Scenario: ST-RPC-001 happy path
  Given prerequisites for "Validate public action payloads through RPC validate endpoint" are satisfied
  When the actor executes the flow through "POST /rpc/validate"
  Then Validation responses return typed success or structured error output without side effects.

Scenario: ST-RPC-001 failure or edge path
  Given a blocking precondition exists for "Validate public action payloads through RPC validate endpoint"
  When the actor executes the flow through "POST /rpc/validate"
  Then If action name is unknown, endpoint returns typed contract mismatch error.
```

#### Evidence of Done
- Validation output is consistent with action input schemas.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-RPC-002 — Execute public actions through RPC run endpoint

#### Story ID
`ST-RPC-002`

#### Title
Execute public actions through RPC run endpoint

#### Persona
Integration Developer

#### Priority
MVP Must

#### Primary Route/API
`POST /rpc/run`

#### Requirement Links
R12

#### Source Spec Links
specs/10_web_ui_and_routes.md, specs/32_agent_and_action_catalog.md

#### Dependencies
none

#### Story
As an integration developer, I want a typed run endpoint so that automation clients can execute supported actions programmatically.

#### Acceptance Criteria
1. `/rpc/run` executes allowed product actions with typed output payloads.
2. Execution responses include run or action identifiers needed for follow-up operations.
3. If action execution fails, endpoint returns typed error taxonomy response without ambiguous status.

#### Verification Scenarios
```gherkin
Scenario: ST-RPC-002 happy path
  Given prerequisites for "Execute public actions through RPC run endpoint" are satisfied
  When the actor executes the flow through "POST /rpc/run"
  Then Execution responses include run or action identifiers needed for follow-up operations.

Scenario: ST-RPC-002 failure or edge path
  Given a blocking precondition exists for "Execute public actions through RPC run endpoint"
  When the actor executes the flow through "POST /rpc/run"
  Then If action execution fails, endpoint returns typed error taxonomy response without ambiguous status.
```

#### Evidence of Done
- RPC run responses are stable across repeated contract-compliant calls.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-RPC-003 — Enforce auth mode policy on RPC actions

#### Story ID
`ST-RPC-003`

#### Title
Enforce auth mode policy on RPC actions

#### Persona
Integration Developer

#### Priority
MVP Must

#### Primary Route/API
`POST /rpc/run`

#### Requirement Links
R1, R10, R12

#### Source Spec Links
specs/60_security_and_auth.md, specs/32_agent_and_action_catalog.md

#### Dependencies
ST-AUTH-004, ST-AUTH-005

#### Story
As an integration developer, I want RPC actions to enforce auth mode policy so that unauthorized callers cannot execute sensitive actions.

#### Acceptance Criteria
1. RPC endpoints evaluate session bearer and API key modes according to action policy requirements.
2. Authorized mode combinations execute while disallowed combinations return typed authorization errors.
3. If actor context is missing, the request fails closed and does not execute action code.

#### Verification Scenarios
```gherkin
Scenario: ST-RPC-003 happy path
  Given prerequisites for "Enforce auth mode policy on RPC actions" are satisfied
  When the actor executes the flow through "POST /rpc/run"
  Then Authorized mode combinations execute while disallowed combinations return typed authorization errors.

Scenario: ST-RPC-003 failure or edge path
  Given a blocking precondition exists for "Enforce auth mode policy on RPC actions"
  When the actor executes the flow through "POST /rpc/run"
  Then If actor context is missing, the request fails closed and does not execute action code.
```

#### Evidence of Done
- RPC logs capture resolved auth mode and policy decision.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-RPC-004 — Return typed validation errors without leaking secrets

#### Story ID
`ST-RPC-004`

#### Title
Return typed validation errors without leaking secrets

#### Persona
Integration Developer

#### Priority
MVP Must

#### Primary Route/API
`POST /rpc/validate`

#### Requirement Links
R10, R12

#### Source Spec Links
specs/60_security_and_auth.md, specs/32_agent_and_action_catalog.md

#### Dependencies
ST-RPC-001

#### Story
As an integration developer, I want validation errors to be typed and safe so that debugging is possible without secret exposure.

#### Acceptance Criteria
1. Validation failures use structured error schema with machine-readable reason codes.
2. Error payloads redact or omit sensitive values from request and environment context.
3. If redaction fails during error serialization, response falls back to generic safe error payload.

#### Verification Scenarios
```gherkin
Scenario: ST-RPC-004 happy path
  Given prerequisites for "Return typed validation errors without leaking secrets" are satisfied
  When the actor executes the flow through "POST /rpc/validate"
  Then Error payloads redact or omit sensitive values from request and environment context.

Scenario: ST-RPC-004 failure or edge path
  Given a blocking precondition exists for "Return typed validation errors without leaking secrets"
  When the actor executes the flow through "POST /rpc/validate"
  Then If redaction fails during error serialization, response falls back to generic safe error payload.
```

#### Evidence of Done
- Validation error samples contain no plaintext secret values.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-RPC-005 — Return typed execution errors aligned with shared taxonomy

#### Story ID
`ST-RPC-005`

#### Title
Return typed execution errors aligned with shared taxonomy

#### Persona
Integration Developer

#### Priority
MVP Must

#### Primary Route/API
`POST /rpc/run`

#### Requirement Links
R5, R12

#### Source Spec Links
specs/30_workflow_system_overview.md, specs/32_agent_and_action_catalog.md

#### Dependencies
ST-RPC-002

#### Story
As an integration developer, I want execution errors mapped to shared taxonomy so that clients can implement deterministic retry logic.

#### Acceptance Criteria
1. RPC run failures return taxonomy codes like validation_error authorization_error execution_error timeout and policy_violation.
2. Error payloads include correlation metadata for linking to run artifacts when applicable.
3. If internal exception mapping fails, response still returns a typed generic execution_error code.

#### Verification Scenarios
```gherkin
Scenario: ST-RPC-005 happy path
  Given prerequisites for "Return typed execution errors aligned with shared taxonomy" are satisfied
  When the actor executes the flow through "POST /rpc/run"
  Then Error payloads include correlation metadata for linking to run artifacts when applicable.

Scenario: ST-RPC-005 failure or edge path
  Given a blocking precondition exists for "Return typed execution errors aligned with shared taxonomy"
  When the actor executes the flow through "POST /rpc/run"
  Then If internal exception mapping fails, response still returns a typed generic execution_error code.
```

#### Evidence of Done
- Client integration tests can branch correctly on returned taxonomy codes.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-RPC-006 — Generate TypeScript client coverage for required action inventory

#### Story ID
`ST-RPC-006`

#### Title
Generate TypeScript client coverage for required action inventory

#### Persona
Integration Developer

#### Priority
MVP Must

#### Primary Route/API
`assets/js/ash_rpc.ts`

#### Requirement Links
R12

#### Source Spec Links
specs/32_agent_and_action_catalog.md, specs/20_ash_domain_model.md

#### Dependencies
ST-RPC-001, ST-RPC-002

#### Story
As an integration developer, I want generated TypeScript client parity so that frontend and external automation stay type-safe.

#### Acceptance Criteria
1. Generated `assets/js/ash_rpc.ts` contains typed signatures for required public action inventory.
2. Generation process updates client definitions when action contracts change.
3. If an inventory action is missing in generated client, coverage check fails with explicit missing action list.

#### Verification Scenarios
```gherkin
Scenario: ST-RPC-006 happy path
  Given prerequisites for "Generate TypeScript client coverage for required action inventory" are satisfied
  When the actor executes the flow through "assets/js/ash_rpc.ts"
  Then Generation process updates client definitions when action contracts change.

Scenario: ST-RPC-006 failure or edge path
  Given a blocking precondition exists for "Generate TypeScript client coverage for required action inventory"
  When the actor executes the flow through "assets/js/ash_rpc.ts"
  Then If an inventory action is missing in generated client, coverage check fails with explicit missing action list.
```

#### Evidence of Done
- Client file and action inventory report show matching coverage.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-RPC-007 — Expose RPC inventory version and mismatch guidance

#### Story ID
`ST-RPC-007`

#### Title
Expose RPC inventory version and mismatch guidance

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Should

#### Primary Route/API
`/settings/api`

#### Requirement Links
R12

#### Source Spec Links
specs/20_ash_domain_model.md, specs/61_configuration_and_deployment.md

#### Dependencies
ST-RPC-006

#### Story
As an OSS maintainer, I want inventory version visibility so that automation client mismatch issues are diagnosable.

#### Acceptance Criteria
1. Settings API page shows current RPC inventory version from system configuration.
2. Version mismatch guidance explains required client regeneration or migration action.
3. If version metadata is unavailable, page shows degraded status and remediation path.

#### Verification Scenarios
```gherkin
Scenario: ST-RPC-007 happy path
  Given prerequisites for "Expose RPC inventory version and mismatch guidance" are satisfied
  When the actor executes the flow through "/settings/api"
  Then Version mismatch guidance explains required client regeneration or migration action.

Scenario: ST-RPC-007 failure or edge path
  Given a blocking precondition exists for "Expose RPC inventory version and mismatch guidance"
  When the actor executes the flow through "/settings/api"
  Then If version metadata is unavailable, page shows degraded status and remediation path.
```

#### Evidence of Done
- Settings UI displays stable inventory version metadata.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-RPC-008 — Show RPC endpoint health and coverage warnings in settings

#### Story ID
`ST-RPC-008`

#### Title
Show RPC endpoint health and coverage warnings in settings

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Should

#### Primary Route/API
`/settings/api`

#### Requirement Links
R9, R12

#### Source Spec Links
specs/10_web_ui_and_routes.md, specs/61_configuration_and_deployment.md

#### Dependencies
ST-RPC-001

#### Story
As an OSS maintainer, I want RPC status visibility in settings so that integration readiness can be validated quickly.

#### Acceptance Criteria
1. Settings API page reports `/rpc/run` and `/rpc/validate` availability status.
2. Coverage warnings are shown when required action inventory parity checks fail.
3. If RPC health checks timeout, status degrades safely with retry guidance.

#### Verification Scenarios
```gherkin
Scenario: ST-RPC-008 happy path
  Given prerequisites for "Show RPC endpoint health and coverage warnings in settings" are satisfied
  When the actor executes the flow through "/settings/api"
  Then Coverage warnings are shown when required action inventory parity checks fail.

Scenario: ST-RPC-008 failure or edge path
  Given a blocking precondition exists for "Show RPC endpoint health and coverage warnings in settings"
  When the actor executes the flow through "/settings/api"
  Then If RPC health checks timeout, status degrades safely with retry guidance.
```

#### Evidence of Done
- Settings API diagnostics provide actionable readiness indicators.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

## Story Count

- 8 stories
