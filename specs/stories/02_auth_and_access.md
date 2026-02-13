# 02 — Auth and Access Stories

Atomic MVP stories for single-user AshAuth, session boundaries, and API credential usage.

## Story Inventory

### ST-AUTH-001 — Sign in owner via browser session

#### Story ID
`ST-AUTH-001`

#### Title
Sign in owner via browser session

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/dashboard`

#### Requirement Links
R1

#### Source Spec Links
specs/60_security_and_auth.md, specs/02_requirements_and_scope.md

#### Dependencies
ST-ONB-004

#### Story
As an OSS maintainer, I want owner sign-in to establish an authenticated browser session so that protected routes are usable.

#### Acceptance Criteria
1. Valid owner credentials create an authenticated session for browser navigation.
2. After sign-in, `/dashboard` and other protected routes load without secondary auth prompts.
3. If credentials are invalid, session creation is denied with a typed authentication error.

#### Verification Scenarios
```gherkin
Scenario: ST-AUTH-001 happy path
  Given prerequisites for "Sign in owner via browser session" are satisfied
  When the actor executes the flow through "/dashboard"
  Then After sign-in, `/dashboard` and other protected routes load without secondary auth prompts.

Scenario: ST-AUTH-001 failure or edge path
  Given a blocking precondition exists for "Sign in owner via browser session"
  When the actor executes the flow through "/dashboard"
  Then If credentials are invalid, session creation is denied with a typed authentication error.
```

#### Evidence of Done
- Session cookie presence and protected route access confirm successful sign-in.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-AUTH-002 — Enforce auth boundary on protected LiveView routes

#### Story ID
`ST-AUTH-002`

#### Title
Enforce auth boundary on protected LiveView routes

#### Persona
Security-Conscious Engineering Lead (P3)

#### Priority
MVP Must

#### Primary Route/API
`/dashboard`

#### Requirement Links
R1, R10

#### Source Spec Links
specs/10_web_ui_and_routes.md, specs/60_security_and_auth.md

#### Dependencies
ST-AUTH-001

#### Story
As a security-conscious engineering lead, I want protected routes to require owner session context so that unauthenticated access is blocked.

#### Acceptance Criteria
1. Protected LiveView routes reject unauthenticated requests and redirect to auth entry flow.
2. Authenticated owner session requests resolve protected routes normally without bypassing policy checks.
3. If session context is missing or expired, access is denied and no protected data is rendered.

#### Verification Scenarios
```gherkin
Scenario: ST-AUTH-002 happy path
  Given prerequisites for "Enforce auth boundary on protected LiveView routes" are satisfied
  When the actor executes the flow through "/dashboard"
  Then Authenticated owner session requests resolve protected routes normally without bypassing policy checks.

Scenario: ST-AUTH-002 failure or edge path
  Given a blocking precondition exists for "Enforce auth boundary on protected LiveView routes"
  When the actor executes the flow through "/dashboard"
  Then If session context is missing or expired, access is denied and no protected data is rendered.
```

#### Evidence of Done
- Route behavior logs indicate explicit allow or deny outcomes for auth boundary checks.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-AUTH-003 — Apply CSRF protection to browser mutating flows

#### Story ID
`ST-AUTH-003`

#### Title
Apply CSRF protection to browser mutating flows

#### Persona
Security-Conscious Engineering Lead (P3)

#### Priority
MVP Must

#### Primary Route/API
`/settings`

#### Requirement Links
R1, R10

#### Source Spec Links
specs/60_security_and_auth.md, specs/10_web_ui_and_routes.md

#### Dependencies
ST-AUTH-001

#### Story
As a security-conscious engineering lead, I want CSRF protection on browser mutations so that cross-site request attacks are blocked.

#### Acceptance Criteria
1. Browser POST PUT PATCH DELETE operations require valid CSRF tokens.
2. Valid session requests with matching CSRF token mutate state successfully.
3. If CSRF token is missing or invalid, mutation is blocked and state remains unchanged.

#### Verification Scenarios
```gherkin
Scenario: ST-AUTH-003 happy path
  Given prerequisites for "Apply CSRF protection to browser mutating flows" are satisfied
  When the actor executes the flow through "/settings"
  Then Valid session requests with matching CSRF token mutate state successfully.

Scenario: ST-AUTH-003 failure or edge path
  Given a blocking precondition exists for "Apply CSRF protection to browser mutating flows"
  When the actor executes the flow through "/settings"
  Then If CSRF token is missing or invalid, mutation is blocked and state remains unchanged.
```

#### Evidence of Done
- Security logs and response codes show CSRF validation outcomes.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-AUTH-004 — Authorize RPC access with bearer tokens

#### Story ID
`ST-AUTH-004`

#### Title
Authorize RPC access with bearer tokens

#### Persona
Integration Developer

#### Priority
MVP Must

#### Primary Route/API
`POST /rpc/run`

#### Requirement Links
R1, R12

#### Source Spec Links
specs/60_security_and_auth.md, specs/10_web_ui_and_routes.md

#### Dependencies
none

#### Story
As an integration developer, I want bearer-token authentication for RPC requests so that automation clients can call product actions securely.

#### Acceptance Criteria
1. Bearer token actor context is accepted for permitted RPC actions.
2. Authorized bearer requests execute action policy checks and return typed responses.
3. If bearer token is invalid expired or revoked, RPC returns typed authorization failure.

#### Verification Scenarios
```gherkin
Scenario: ST-AUTH-004 happy path
  Given prerequisites for "Authorize RPC access with bearer tokens" are satisfied
  When the actor executes the flow through "POST /rpc/run"
  Then Authorized bearer requests execute action policy checks and return typed responses.

Scenario: ST-AUTH-004 failure or edge path
  Given a blocking precondition exists for "Authorize RPC access with bearer tokens"
  When the actor executes the flow through "POST /rpc/run"
  Then If bearer token is invalid expired or revoked, RPC returns typed authorization failure.
```

#### Evidence of Done
- RPC responses include actor-auth mode metadata without leaking token values.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-AUTH-005 — Authorize RPC access with API keys

#### Story ID
`ST-AUTH-005`

#### Title
Authorize RPC access with API keys

#### Persona
Integration Developer

#### Priority
MVP Must

#### Primary Route/API
`POST /rpc/validate`

#### Requirement Links
R1, R12

#### Source Spec Links
specs/60_security_and_auth.md, specs/20_ash_domain_model.md

#### Dependencies
none

#### Story
As an integration developer, I want API key authentication for RPC calls so that service-style integrations can operate without browser sessions.

#### Acceptance Criteria
1. API key credentials resolve actor context for action policies that allow API key mode.
2. Valid API key requests can validate and run permitted actions through RPC endpoints.
3. If API key is revoked expired or unknown, RPC returns typed authorization errors and performs no action.

#### Verification Scenarios
```gherkin
Scenario: ST-AUTH-005 happy path
  Given prerequisites for "Authorize RPC access with API keys" are satisfied
  When the actor executes the flow through "POST /rpc/validate"
  Then Valid API key requests can validate and run permitted actions through RPC endpoints.

Scenario: ST-AUTH-005 failure or edge path
  Given a blocking precondition exists for "Authorize RPC access with API keys"
  When the actor executes the flow through "POST /rpc/validate"
  Then If API key is revoked expired or unknown, RPC returns typed authorization errors and performs no action.
```

#### Evidence of Done
- API key audit records include usage timestamp and endpoint metadata.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-AUTH-006 — Expire and revoke tokens as first-class actions

#### Story ID
`ST-AUTH-006`

#### Title
Expire and revoke tokens as first-class actions

#### Persona
Security-Conscious Engineering Lead (P3)

#### Priority
MVP Must

#### Primary Route/API
`/settings/security`

#### Requirement Links
R1, R10

#### Source Spec Links
specs/20_ash_domain_model.md, specs/62_security_playbook.md

#### Dependencies
ST-AUTH-004

#### Story
As a security-conscious engineering lead, I want token expiry and revocation controls so that compromised credentials can be neutralized quickly.

#### Acceptance Criteria
1. Token resources expose expiry metadata and revocation operations in product actions.
2. Revoked tokens stop authorizing requests immediately across API surfaces.
3. If revocation action fails, token state remains unchanged and a typed recovery instruction is returned.

#### Verification Scenarios
```gherkin
Scenario: ST-AUTH-006 happy path
  Given prerequisites for "Expire and revoke tokens as first-class actions" are satisfied
  When the actor executes the flow through "/settings/security"
  Then Revoked tokens stop authorizing requests immediately across API surfaces.

Scenario: ST-AUTH-006 failure or edge path
  Given a blocking precondition exists for "Expire and revoke tokens as first-class actions"
  When the actor executes the flow through "/settings/security"
  Then If revocation action fails, token state remains unchanged and a typed recovery instruction is returned.
```

#### Evidence of Done
- Token status screens and audit data show revocation effect with timestamps.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-AUTH-007 — Invalidate session on sign out

#### Story ID
`ST-AUTH-007`

#### Title
Invalidate session on sign out

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/settings`

#### Requirement Links
R1, R10

#### Source Spec Links
specs/60_security_and_auth.md, specs/02_requirements_and_scope.md

#### Dependencies
ST-AUTH-001

#### Story
As an OSS maintainer, I want sign-out to invalidate active session state so that browser access ends immediately.

#### Acceptance Criteria
1. Sign-out clears session credentials and owner context from browser state.
2. Requests to protected routes after sign-out are redirected to authentication flow.
3. If session invalidation cannot complete, the user receives explicit retry guidance and no partial sign-out state remains.

#### Verification Scenarios
```gherkin
Scenario: ST-AUTH-007 happy path
  Given prerequisites for "Invalidate session on sign out" are satisfied
  When the actor executes the flow through "/settings"
  Then Requests to protected routes after sign-out are redirected to authentication flow.

Scenario: ST-AUTH-007 failure or edge path
  Given a blocking precondition exists for "Invalidate session on sign out"
  When the actor executes the flow through "/settings"
  Then If session invalidation cannot complete, the user receives explicit retry guidance and no partial sign-out state remains.
```

#### Evidence of Done
- Post-sign-out protected route access is consistently denied.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-AUTH-008 — Provide owner recovery bootstrap path

#### Story ID
`ST-AUTH-008`

#### Title
Provide owner recovery bootstrap path

#### Persona
Security-Conscious Engineering Lead (P3)

#### Priority
MVP Should

#### Primary Route/API
`/setup`

#### Requirement Links
R1, R2, R10

#### Source Spec Links
specs/60_security_and_auth.md, specs/62_security_playbook.md

#### Dependencies
ST-ONB-004

#### Story
As a security-conscious engineering lead, I want a documented owner recovery path so that instance access can be restored after credential loss.

#### Acceptance Criteria
1. Recovery flow requires explicit verification steps before owner credential reset actions.
2. Successful recovery produces new valid owner credentials and records recovery audit metadata.
3. If verification fails, recovery does not mutate owner state and returns a safe denial reason.

#### Verification Scenarios
```gherkin
Scenario: ST-AUTH-008 happy path
  Given prerequisites for "Provide owner recovery bootstrap path" are satisfied
  When the actor executes the flow through "/setup"
  Then Successful recovery produces new valid owner credentials and records recovery audit metadata.

Scenario: ST-AUTH-008 failure or edge path
  Given a blocking precondition exists for "Provide owner recovery bootstrap path"
  When the actor executes the flow through "/setup"
  Then If verification fails, recovery does not mutate owner state and returns a safe denial reason.
```

#### Evidence of Done
- Recovery runbook checks and audit events show successful drill completion.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

## Story Count

- 8 stories
