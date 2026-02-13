# 08 — Issue Bot and Agent Control Stories

Atomic MVP stories for support-agent configuration, webhook-triggered triage, and response publishing.

## Story Inventory

### ST-BOT-001 — Enable or disable Issue Bot per project

#### Story ID
`ST-BOT-001`

#### Title
Enable or disable Issue Bot per project

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/agents`

#### Requirement Links
R8, R13

#### Source Spec Links
specs/10_web_ui_and_routes.md, specs/20_ash_domain_model.md

#### Dependencies
none

#### Story
As an OSS maintainer, I want per-project Issue Bot toggles so that automation can be tuned by repository risk profile.

#### Acceptance Criteria
1. Agents page exposes enable and disable controls for Issue Bot on each project.
2. Config changes persist to `SupportAgentConfig.enabled` and are reflected immediately in UI state.
3. If config persistence fails, enabled state remains unchanged and typed error feedback is shown.

#### Verification Scenarios
```gherkin
Scenario: ST-BOT-001 happy path
  Given prerequisites for "Enable or disable Issue Bot per project" are satisfied
  When the actor executes the flow through "/agents"
  Then Config changes persist to `SupportAgentConfig.enabled` and are reflected immediately in UI state.

Scenario: ST-BOT-001 failure or edge path
  Given a blocking precondition exists for "Enable or disable Issue Bot per project"
  When the actor executes the flow through "/agents"
  Then If config persistence fails, enabled state remains unchanged and typed error feedback is shown.
```

#### Evidence of Done
- Agents view and project config both show consistent Issue Bot enabled state.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-BOT-002 — Configure Issue Bot webhook events per project

#### Story ID
`ST-BOT-002`

#### Title
Configure Issue Bot webhook events per project

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/agents`

#### Requirement Links
R8

#### Source Spec Links
specs/20_ash_domain_model.md, specs/50_github_integration.md

#### Dependencies
ST-BOT-001

#### Story
As an OSS maintainer, I want configurable webhook event lists so that Issue Bot triggers only on desired issue activity.

#### Acceptance Criteria
1. Project Issue Bot config supports explicit event list updates for supported webhook events.
2. Trigger pipeline uses stored event list when evaluating inbound deliveries.
3. If unsupported event values are submitted, config update is rejected with typed validation errors.

#### Verification Scenarios
```gherkin
Scenario: ST-BOT-002 happy path
  Given prerequisites for "Configure Issue Bot webhook events per project" are satisfied
  When the actor executes the flow through "/agents"
  Then Trigger pipeline uses stored event list when evaluating inbound deliveries.

Scenario: ST-BOT-002 failure or edge path
  Given a blocking precondition exists for "Configure Issue Bot webhook events per project"
  When the actor executes the flow through "/agents"
  Then If unsupported event values are submitted, config update is rejected with typed validation errors.
```

#### Evidence of Done
- Stored webhook event lists match selected project policy settings.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-BOT-003 — Configure approval mode for auto-post versus manual gate

#### Story ID
`ST-BOT-003`

#### Title
Configure approval mode for auto-post versus manual gate

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/agents`

#### Requirement Links
R8, R7

#### Source Spec Links
specs/10_web_ui_and_routes.md, specs/31_builtin_workflows.md

#### Dependencies
ST-BOT-001

#### Story
As an OSS maintainer, I want approval policy controls for Issue Bot so that response posting risk is managed explicitly.

#### Acceptance Criteria
1. Agents page supports per-project selection of auto-post or approval-required mode.
2. Selected policy is consumed by issue triage workflow when deciding post behavior.
3. If policy update fails, previous policy remains active and UI shows failure context.

#### Verification Scenarios
```gherkin
Scenario: ST-BOT-003 happy path
  Given prerequisites for "Configure approval mode for auto-post versus manual gate" are satisfied
  When the actor executes the flow through "/agents"
  Then Selected policy is consumed by issue triage workflow when deciding post behavior.

Scenario: ST-BOT-003 failure or edge path
  Given a blocking precondition exists for "Configure approval mode for auto-post versus manual gate"
  When the actor executes the flow through "/agents"
  Then If policy update fails, previous policy remains active and UI shows failure context.
```

#### Evidence of Done
- Issue Bot config output includes approval policy and last updated metadata.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-BOT-004 — Trigger issue_triage on issues.opened deliveries

#### Story ID
`ST-BOT-004`

#### Title
Trigger issue_triage on issues.opened deliveries

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`POST /api/github/webhooks`

#### Requirement Links
R8, R3

#### Source Spec Links
specs/50_github_integration.md, specs/31_builtin_workflows.md

#### Dependencies
ST-GH-006, ST-BOT-001

#### Story
As an OSS maintainer, I want opened issues to trigger triage workflows so that new backlog items receive immediate automation support.

#### Acceptance Criteria
1. Verified `issues.opened` deliveries for enabled projects create tracked `issue_triage` runs.
2. Run metadata includes webhook trigger context and source issue identifiers.
3. If project Issue Bot is disabled, delivery is recorded as no-op and no run is created.

#### Verification Scenarios
```gherkin
Scenario: ST-BOT-004 happy path
  Given prerequisites for "Trigger issue_triage on issues.opened deliveries" are satisfied
  When the actor executes the flow through "POST /api/github/webhooks"
  Then Run metadata includes webhook trigger context and source issue identifiers.

Scenario: ST-BOT-004 failure or edge path
  Given a blocking precondition exists for "Trigger issue_triage on issues.opened deliveries"
  When the actor executes the flow through "POST /api/github/webhooks"
  Then If project Issue Bot is disabled, delivery is recorded as no-op and no run is created.
```

#### Evidence of Done
- Dashboard and workbench surfaces show newly created Issue Bot runs.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-BOT-005 — Trigger retriage on issues.edited deliveries

#### Story ID
`ST-BOT-005`

#### Title
Trigger retriage on issues.edited deliveries

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`POST /api/github/webhooks`

#### Requirement Links
R8, R3

#### Source Spec Links
specs/50_github_integration.md, specs/31_builtin_workflows.md

#### Dependencies
ST-BOT-004

#### Story
As an OSS maintainer, I want edited issues to trigger retriage so that automation output stays aligned with updated issue context.

#### Acceptance Criteria
1. Verified `issues.edited` deliveries map to retriage behavior according to project policy.
2. Retriage runs link to prior issue analysis artifacts for comparison context.
3. If edit event is filtered by project policy, no run is created and reason is recorded.

#### Verification Scenarios
```gherkin
Scenario: ST-BOT-005 happy path
  Given prerequisites for "Trigger retriage on issues.edited deliveries" are satisfied
  When the actor executes the flow through "POST /api/github/webhooks"
  Then Retriage runs link to prior issue analysis artifacts for comparison context.

Scenario: ST-BOT-005 failure or edge path
  Given a blocking precondition exists for "Trigger retriage on issues.edited deliveries"
  When the actor executes the flow through "POST /api/github/webhooks"
  Then If edit event is filtered by project policy, no run is created and reason is recorded.
```

#### Evidence of Done
- Issue history shows retriage run linkage for edited issues.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-BOT-006 — Support optional follow-up triggers from issue comments

#### Story ID
`ST-BOT-006`

#### Title
Support optional follow-up triggers from issue comments

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Should

#### Primary Route/API
`POST /api/github/webhooks`

#### Requirement Links
R8, R3

#### Source Spec Links
specs/50_github_integration.md, specs/31_builtin_workflows.md

#### Dependencies
ST-BOT-002

#### Story
As an OSS maintainer, I want optional issue comment triggers so that follow-up research can run when maintainers request it.

#### Acceptance Criteria
1. When enabled, `issue_comment.created` events can dispatch follow-up workflow actions.
2. Follow-up trigger handling respects project enablement and approval policy controls.
3. If follow-up triggers are disabled, comment events are ignored with auditable no-op status.

#### Verification Scenarios
```gherkin
Scenario: ST-BOT-006 happy path
  Given prerequisites for "Support optional follow-up triggers from issue comments" are satisfied
  When the actor executes the flow through "POST /api/github/webhooks"
  Then Follow-up trigger handling respects project enablement and approval policy controls.

Scenario: ST-BOT-006 failure or edge path
  Given a blocking precondition exists for "Support optional follow-up triggers from issue comments"
  When the actor executes the flow through "POST /api/github/webhooks"
  Then If follow-up triggers are disabled, comment events are ignored with auditable no-op status.
```

#### Evidence of Done
- Webhook processing records follow-up trigger decision outcomes.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-BOT-007 — Persist triage research and response draft artifacts

#### Story ID
`ST-BOT-007`

#### Title
Persist triage research and response draft artifacts

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/projects/:id/runs/:run_id`

#### Requirement Links
R8, R9

#### Source Spec Links
specs/31_builtin_workflows.md, specs/20_ash_domain_model.md

#### Dependencies
ST-BOT-004

#### Story
As an OSS maintainer, I want Issue Bot outputs persisted so that response quality can be reviewed and audited.

#### Acceptance Criteria
1. Issue triage workflow stores classification research summary and proposed response artifacts.
2. Artifacts are linked to workflow run and source issue metadata.
3. If artifact persistence fails, run is marked failed with typed persistence error and partial state preserved.

#### Verification Scenarios
```gherkin
Scenario: ST-BOT-007 happy path
  Given prerequisites for "Persist triage research and response draft artifacts" are satisfied
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then Artifacts are linked to workflow run and source issue metadata.

Scenario: ST-BOT-007 failure or edge path
  Given a blocking precondition exists for "Persist triage research and response draft artifacts"
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then If artifact persistence fails, run is marked failed with typed persistence error and partial state preserved.
```

#### Evidence of Done
- Run detail shows triage artifact set for each Issue Bot execution.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-BOT-008 — Post approved or auto-approved responses and store GitHub URL

#### Story ID
`ST-BOT-008`

#### Title
Post approved or auto-approved responses and store GitHub URL

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/projects/:id/runs/:run_id`

#### Requirement Links
R8, R3, R9

#### Source Spec Links
specs/31_builtin_workflows.md, specs/50_github_integration.md

#### Dependencies
ST-BOT-003, ST-BOT-007

#### Story
As an OSS maintainer, I want response posting outcomes persisted so that external side effects are traceable.

#### Acceptance Criteria
1. Approved or auto-approved Issue Bot runs post comments through GitHub integration path.
2. Posted response URL and metadata are persisted as run artifacts and surfaced in UI.
3. If posting fails, run captures typed provider or auth error and does not mark post as successful.

#### Verification Scenarios
```gherkin
Scenario: ST-BOT-008 happy path
  Given prerequisites for "Post approved or auto-approved responses and store GitHub URL" are satisfied
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then Posted response URL and metadata are persisted as run artifacts and surfaced in UI.

Scenario: ST-BOT-008 failure or edge path
  Given a blocking precondition exists for "Post approved or auto-approved responses and store GitHub URL"
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then If posting fails, run captures typed provider or auth error and does not mark post as successful.
```

#### Evidence of Done
- Run artifacts include final posted comment URL when post succeeds.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

## Story Count

- 8 stories
