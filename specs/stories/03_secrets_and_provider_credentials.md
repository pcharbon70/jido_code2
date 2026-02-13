# 03 — Secret and Provider Credential Stories

Atomic MVP stories for encrypted secret handling, redaction coverage, and provider lifecycle operations.

## Story Inventory

### ST-SEC-001 — Persist operational secrets only as encrypted SecretRef entries

#### Story ID
`ST-SEC-001`

#### Title
Persist operational secrets only as encrypted SecretRef entries

#### Persona
Security-Conscious Engineering Lead (P3)

#### Priority
MVP Must

#### Primary Route/API
`/settings/security`

#### Requirement Links
R10

#### Source Spec Links
specs/20_ash_domain_model.md, specs/60_security_and_auth.md

#### Dependencies
none

#### Story
As a security-conscious engineering lead, I want operational secrets stored only in encrypted fields so that database compromise risk is reduced.

#### Acceptance Criteria
1. Secret persistence writes operational values into encrypted `ciphertext` fields only.
2. Secret metadata remains queryable without exposing plaintext values.
3. If encryption configuration is unavailable, secret persistence is blocked with typed remediation guidance.

#### Verification Scenarios
```gherkin
Scenario: ST-SEC-001 happy path
  Given prerequisites for "Persist operational secrets only as encrypted SecretRef entries" are satisfied
  When the actor executes the flow through "/settings/security"
  Then Secret metadata remains queryable without exposing plaintext values.

Scenario: ST-SEC-001 failure or edge path
  Given a blocking precondition exists for "Persist operational secrets only as encrypted SecretRef entries"
  When the actor executes the flow through "/settings/security"
  Then If encryption configuration is unavailable, secret persistence is blocked with typed remediation guidance.
```

#### Evidence of Done
- Stored secret records show encrypted payload plus non-sensitive metadata fields.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-SEC-002 — Reject plaintext secret persistence paths

#### Story ID
`ST-SEC-002`

#### Title
Reject plaintext secret persistence paths

#### Persona
Security-Conscious Engineering Lead (P3)

#### Priority
MVP Must

#### Primary Route/API
`/settings/security`

#### Requirement Links
R10

#### Source Spec Links
specs/03_decisions_and_invariants.md, specs/60_security_and_auth.md

#### Dependencies
ST-SEC-001

#### Story
As a security-conscious engineering lead, I want plaintext secret persistence rejected at action boundaries so that unsafe storage cannot occur accidentally.

#### Acceptance Criteria
1. Actions reject payloads that attempt to store operational secrets in plaintext fields.
2. Rejected writes do not create partial secret records or fallback plaintext storage.
3. If a plaintext persistence attempt is made, the response returns typed policy violation details.

#### Verification Scenarios
```gherkin
Scenario: ST-SEC-002 happy path
  Given prerequisites for "Reject plaintext secret persistence paths" are satisfied
  When the actor executes the flow through "/settings/security"
  Then Rejected writes do not create partial secret records or fallback plaintext storage.

Scenario: ST-SEC-002 failure or edge path
  Given a blocking precondition exists for "Reject plaintext secret persistence paths"
  When the actor executes the flow through "/settings/security"
  Then If a plaintext persistence attempt is made, the response returns typed policy violation details.
```

#### Evidence of Done
- Audit logs show blocked plaintext persistence attempts with actor context.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-SEC-003 — Track key version and rotation metadata on secrets

#### Story ID
`ST-SEC-003`

#### Title
Track key version and rotation metadata on secrets

#### Persona
Security-Conscious Engineering Lead (P3)

#### Priority
MVP Must

#### Primary Route/API
`/settings/security`

#### Requirement Links
R10

#### Source Spec Links
specs/20_ash_domain_model.md, specs/62_security_playbook.md

#### Dependencies
ST-SEC-001

#### Story
As a security-conscious engineering lead, I want key version and rotation timestamps tracked so that secret lifecycle health is auditable.

#### Acceptance Criteria
1. Secret records include `key_version` and `last_rotated_at` metadata after create or rotate operations.
2. Rotation updates metadata atomically with the active encrypted value.
3. If rotation metadata write fails, the rotation is rolled back and prior secret state remains active.

#### Verification Scenarios
```gherkin
Scenario: ST-SEC-003 happy path
  Given prerequisites for "Track key version and rotation metadata on secrets" are satisfied
  When the actor executes the flow through "/settings/security"
  Then Rotation updates metadata atomically with the active encrypted value.

Scenario: ST-SEC-003 failure or edge path
  Given a blocking precondition exists for "Track key version and rotation metadata on secrets"
  When the actor executes the flow through "/settings/security"
  Then If rotation metadata write fails, the rotation is rolled back and prior secret state remains active.
```

#### Evidence of Done
- Secret detail views show current key version and last rotation timestamp.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-SEC-004 — Redact secrets before logger output

#### Story ID
`ST-SEC-004`

#### Title
Redact secrets before logger output

#### Persona
Security-Conscious Engineering Lead (P3)

#### Priority
MVP Must

#### Primary Route/API
`/projects/:id/runs/:run_id`

#### Requirement Links
R10

#### Source Spec Links
specs/60_security_and_auth.md, specs/62_security_playbook.md

#### Dependencies
none

#### Story
As a security-conscious engineering lead, I want redaction applied to logger output so that secret values are not leaked in runtime logs.

#### Acceptance Criteria
1. Log events pass through redaction filters before persistence or transport.
2. Masked values preserve enough context for debugging without exposing secret content.
3. If redaction fails, the event is treated as high-priority security failure and raw secret output is blocked.

#### Verification Scenarios
```gherkin
Scenario: ST-SEC-004 happy path
  Given prerequisites for "Redact secrets before logger output" are satisfied
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then Masked values preserve enough context for debugging without exposing secret content.

Scenario: ST-SEC-004 failure or edge path
  Given a blocking precondition exists for "Redact secrets before logger output"
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then If redaction fails, the event is treated as high-priority security failure and raw secret output is blocked.
```

#### Evidence of Done
- Log samples show masked tokens and no raw secret values.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-SEC-005 — Redact secrets before PubSub and artifact persistence

#### Story ID
`ST-SEC-005`

#### Title
Redact secrets before PubSub and artifact persistence

#### Persona
Security-Conscious Engineering Lead (P3)

#### Priority
MVP Must

#### Primary Route/API
`jido_code:run:<id>`

#### Requirement Links
R10, R9

#### Source Spec Links
specs/30_workflow_system_overview.md, specs/60_security_and_auth.md

#### Dependencies
ST-SEC-004

#### Story
As a security-conscious engineering lead, I want redaction on PubSub and artifact channels so that streamed and persisted outputs remain safe.

#### Acceptance Criteria
1. PubSub payloads and artifact writes apply redaction before publish and save operations.
2. Run detail consumers receive masked data while preserving event integrity and ordering.
3. If redaction cannot complete, publication and persistence are blocked with typed security error.

#### Verification Scenarios
```gherkin
Scenario: ST-SEC-005 happy path
  Given prerequisites for "Redact secrets before PubSub and artifact persistence" are satisfied
  When the actor executes the flow through "jido_code:run:<id>"
  Then Run detail consumers receive masked data while preserving event integrity and ordering.

Scenario: ST-SEC-005 failure or edge path
  Given a blocking precondition exists for "Redact secrets before PubSub and artifact persistence"
  When the actor executes the flow through "jido_code:run:<id>"
  Then If redaction cannot complete, publication and persistence are blocked with typed security error.
```

#### Evidence of Done
- Sample artifacts and stream payloads contain masked sensitive values only.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-SEC-006 — Redact secrets before prompt context and UI rendering

#### Story ID
`ST-SEC-006`

#### Title
Redact secrets before prompt context and UI rendering

#### Persona
Security-Conscious Engineering Lead (P3)

#### Priority
MVP Must

#### Primary Route/API
`/projects/:id/runs/:run_id`

#### Requirement Links
R10, R6

#### Source Spec Links
specs/60_security_and_auth.md, specs/30_workflow_system_overview.md

#### Dependencies
ST-SEC-004

#### Story
As a security-conscious engineering lead, I want prompt and UI redaction coverage so that secret values are not exposed to models or operators.

#### Acceptance Criteria
1. Prompt payload assembly removes or masks sensitive values before LLM calls are made.
2. UI pages render masked placeholders rather than raw secret content in run details and settings.
3. If sensitive values are detected post-render, the page flags a security alert and suppresses unsafe content.

#### Verification Scenarios
```gherkin
Scenario: ST-SEC-006 happy path
  Given prerequisites for "Redact secrets before prompt context and UI rendering" are satisfied
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then UI pages render masked placeholders rather than raw secret content in run details and settings.

Scenario: ST-SEC-006 failure or edge path
  Given a blocking precondition exists for "Redact secrets before prompt context and UI rendering"
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then If sensitive values are detected post-render, the page flags a security alert and suppresses unsafe content.
```

#### Evidence of Done
- Prompt audit artifacts and UI snapshots confirm redacted output behavior.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-SEC-007 — Maintain provider credential health status transitions

#### Story ID
`ST-SEC-007`

#### Title
Maintain provider credential health status transitions

#### Persona
Solo Developer or Small Team Lead (P2)

#### Priority
MVP Must

#### Primary Route/API
`/setup`

#### Requirement Links
R2, R6

#### Source Spec Links
specs/11_onboarding_flow.md, specs/20_ash_domain_model.md

#### Dependencies
ST-ONB-006

#### Story
As a solo developer, I want provider credential status transitions tracked so that provider readiness is visible during setup and operations.

#### Acceptance Criteria
1. Provider verification updates status values among `active` `invalid` `not_set` and `rotating` appropriately.
2. Verification timestamps update on successful checks and remain unchanged on failed checks.
3. If provider check endpoint errors, status moves to invalid with typed provider failure details.

#### Verification Scenarios
```gherkin
Scenario: ST-SEC-007 happy path
  Given prerequisites for "Maintain provider credential health status transitions" are satisfied
  When the actor executes the flow through "/setup"
  Then Verification timestamps update on successful checks and remain unchanged on failed checks.

Scenario: ST-SEC-007 failure or edge path
  Given a blocking precondition exists for "Maintain provider credential health status transitions"
  When the actor executes the flow through "/setup"
  Then If provider check endpoint errors, status moves to invalid with typed provider failure details.
```

#### Evidence of Done
- Provider status views show current state and last verification time.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-SEC-008 — Rotate provider credentials without service downtime

#### Story ID
`ST-SEC-008`

#### Title
Rotate provider credentials without service downtime

#### Persona
Security-Conscious Engineering Lead (P3)

#### Priority
MVP Should

#### Primary Route/API
`/settings/security`

#### Requirement Links
R10, R6

#### Source Spec Links
specs/62_security_playbook.md, specs/20_ash_domain_model.md

#### Dependencies
ST-SEC-003

#### Story
As a security-conscious engineering lead, I want provider credentials rotated safely so that workflow service continuity is maintained during key changes.

#### Acceptance Criteria
1. Rotation introduces new credential version and updates references atomically.
2. In-flight runs continue using valid credential context while new runs adopt rotated credentials.
3. If post-rotation validation fails, credential references roll back and service continues on prior version.

#### Verification Scenarios
```gherkin
Scenario: ST-SEC-008 happy path
  Given prerequisites for "Rotate provider credentials without service downtime" are satisfied
  When the actor executes the flow through "/settings/security"
  Then In-flight runs continue using valid credential context while new runs adopt rotated credentials.

Scenario: ST-SEC-008 failure or edge path
  Given a blocking precondition exists for "Rotate provider credentials without service downtime"
  When the actor executes the flow through "/settings/security"
  Then If post-rotation validation fails, credential references roll back and service continues on prior version.
```

#### Evidence of Done
- Rotation operations show before and after verification status without interruption alarms.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-SEC-009 — Resolve secret source precedence for env and DB references

#### Story ID
`ST-SEC-009`

#### Title
Resolve secret source precedence for env and DB references

#### Persona
Security-Conscious Engineering Lead (P3)

#### Priority
MVP Must

#### Primary Route/API
`/setup`

#### Requirement Links
R10, R11

#### Source Spec Links
specs/61_configuration_and_deployment.md, specs/20_ash_domain_model.md

#### Dependencies
none

#### Story
As a security-conscious engineering lead, I want deterministic secret source precedence so that runtime behavior is predictable across environments.

#### Acceptance Criteria
1. Secret resolution follows documented precedence between env root secrets and encrypted DB references.
2. Resolved source metadata is visible without exposing secret material.
3. If both sources are missing, dependent actions fail fast with typed secret unavailable errors.

#### Verification Scenarios
```gherkin
Scenario: ST-SEC-009 happy path
  Given prerequisites for "Resolve secret source precedence for env and DB references" are satisfied
  When the actor executes the flow through "/setup"
  Then Resolved source metadata is visible without exposing secret material.

Scenario: ST-SEC-009 failure or edge path
  Given a blocking precondition exists for "Resolve secret source precedence for env and DB references"
  When the actor executes the flow through "/setup"
  Then If both sources are missing, dependent actions fail fast with typed secret unavailable errors.
```

#### Evidence of Done
- Diagnostics indicate selected source and resolution outcome for each secret binding.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-SEC-010 — Audit secret lifecycle actions with actor and timestamp

#### Story ID
`ST-SEC-010`

#### Title
Audit secret lifecycle actions with actor and timestamp

#### Persona
Security-Conscious Engineering Lead (P3)

#### Priority
MVP Must

#### Primary Route/API
`/settings/security`

#### Requirement Links
R10

#### Source Spec Links
specs/62_security_playbook.md, specs/60_security_and_auth.md

#### Dependencies
ST-SEC-001

#### Story
As a security-conscious engineering lead, I want secret lifecycle actions audited so that incident forensics are reliable.

#### Acceptance Criteria
1. Create rotate revoke secret actions persist actor and timestamp audit metadata.
2. Audit records include action type target secret and outcome status.
3. If audit persistence fails, lifecycle action is treated as failed and no silent mutation occurs.

#### Verification Scenarios
```gherkin
Scenario: ST-SEC-010 happy path
  Given prerequisites for "Audit secret lifecycle actions with actor and timestamp" are satisfied
  When the actor executes the flow through "/settings/security"
  Then Audit records include action type target secret and outcome status.

Scenario: ST-SEC-010 failure or edge path
  Given a blocking precondition exists for "Audit secret lifecycle actions with actor and timestamp"
  When the actor executes the flow through "/settings/security"
  Then If audit persistence fails, lifecycle action is treated as failed and no silent mutation occurs.
```

#### Evidence of Done
- Security audit views show complete lifecycle history for each secret reference.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

## Story Count

- 10 stories
