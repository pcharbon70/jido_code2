# 09 — Observability and Artifact Stories

Atomic MVP stories for live visibility, artifact browsing, and failure analytics.

## Story Inventory

### ST-OBS-001 — Show recent run summaries on dashboard

#### Story ID
`ST-OBS-001`

#### Title
Show recent run summaries on dashboard

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/dashboard`

#### Requirement Links
R9, R13

#### Source Spec Links
specs/10_web_ui_and_routes.md, specs/30_workflow_system_overview.md

#### Dependencies
none

#### Story
As an OSS maintainer, I want dashboard run summaries so that I can monitor system throughput at a glance.

#### Acceptance Criteria
1. Dashboard renders recent runs with status and recency indicators.
2. Run summary data updates as new runs start complete or fail.
3. If summary feed is stale, dashboard shows freshness warning and manual refresh control.

#### Verification Scenarios
```gherkin
Scenario: ST-OBS-001 happy path
  Given prerequisites for "Show recent run summaries on dashboard" are satisfied
  When the actor executes the flow through "/dashboard"
  Then Run summary data updates as new runs start complete or fail.

Scenario: ST-OBS-001 failure or edge path
  Given a blocking precondition exists for "Show recent run summaries on dashboard"
  When the actor executes the flow through "/dashboard"
  Then If summary feed is stale, dashboard shows freshness warning and manual refresh control.
```

#### Evidence of Done
- Dashboard widgets match current persisted run records.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-OBS-002 — Render run detail timeline with per-step duration

#### Story ID
`ST-OBS-002`

#### Title
Render run detail timeline with per-step duration

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/projects/:id/runs/:run_id`

#### Requirement Links
R9

#### Source Spec Links
specs/30_workflow_system_overview.md, specs/10_web_ui_and_routes.md

#### Dependencies
ST-WF-003

#### Story
As an OSS maintainer, I want per-step run timelines so that I can diagnose slow or failing execution segments.

#### Acceptance Criteria
1. Run detail timeline displays ordered step transitions with durations and statuses.
2. Timeline updates in near real time while run is active.
3. If duration data is missing for a step, timeline marks unknown duration without breaking render.

#### Verification Scenarios
```gherkin
Scenario: ST-OBS-002 happy path
  Given prerequisites for "Render run detail timeline with per-step duration" are satisfied
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then Timeline updates in near real time while run is active.

Scenario: ST-OBS-002 failure or edge path
  Given a blocking precondition exists for "Render run detail timeline with per-step duration"
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then If duration data is missing for a step, timeline marks unknown duration without breaking render.
```

#### Evidence of Done
- Timeline output remains consistent with emitted run events.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-OBS-003 — Stream Forge session output with continuity guarantees

#### Story ID
`ST-OBS-003`

#### Title
Stream Forge session output with continuity guarantees

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`forge:session:<id>`

#### Requirement Links
R9, R6

#### Source Spec Links
specs/41_forge_integration.md, specs/30_workflow_system_overview.md

#### Dependencies
ST-WF-004

#### Story
As an OSS maintainer, I want continuous Forge output streaming so that active execution context is visible without gaps.

#### Acceptance Criteria
1. Run detail subscribes to active Forge session topics during execution steps.
2. Output ordering is preserved and discontinuities are labeled if reconnection occurs.
3. If stream subscription fails, run detail surfaces degraded mode and retains persisted logs.

#### Verification Scenarios
```gherkin
Scenario: ST-OBS-003 happy path
  Given prerequisites for "Stream Forge session output with continuity guarantees" are satisfied
  When the actor executes the flow through "forge:session:<id>"
  Then Output ordering is preserved and discontinuities are labeled if reconnection occurs.

Scenario: ST-OBS-003 failure or edge path
  Given a blocking precondition exists for "Stream Forge session output with continuity guarantees"
  When the actor executes the flow through "forge:session:<id>"
  Then If stream subscription fails, run detail surfaces degraded mode and retains persisted logs.
```

#### Evidence of Done
- Captured artifacts preserve streamed output continuity metadata.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-OBS-004 — Browse run artifacts for logs diffs reports and PR outputs

#### Story ID
`ST-OBS-004`

#### Title
Browse run artifacts for logs diffs reports and PR outputs

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/projects/:id/runs/:run_id`

#### Requirement Links
R9

#### Source Spec Links
specs/30_workflow_system_overview.md, specs/51_git_and_pr_flow.md

#### Dependencies
ST-WF-003

#### Story
As an OSS maintainer, I want artifact browsing in run detail so that debugging and review do not require external tooling.

#### Acceptance Criteria
1. Run detail exposes artifact categories for logs diff summaries reports and PR metadata.
2. Artifact entries are downloadable or viewable with stable identifiers.
3. If an artifact is unavailable, the UI reports missing artifact status without failing the entire page.

#### Verification Scenarios
```gherkin
Scenario: ST-OBS-004 happy path
  Given prerequisites for "Browse run artifacts for logs diffs reports and PR outputs" are satisfied
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then Artifact entries are downloadable or viewable with stable identifiers.

Scenario: ST-OBS-004 failure or edge path
  Given a blocking precondition exists for "Browse run artifacts for logs diffs reports and PR outputs"
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then If an artifact is unavailable, the UI reports missing artifact status without failing the entire page.
```

#### Evidence of Done
- Artifact browser contents match persisted artifact records for the run.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-OBS-005 — Display recent run outcomes in workbench context rows

#### Story ID
`ST-OBS-005`

#### Title
Display recent run outcomes in workbench context rows

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/workbench`

#### Requirement Links
R9, R13

#### Source Spec Links
specs/10_web_ui_and_routes.md, specs/ux/02_user_journey.md

#### Dependencies
ST-WB-001

#### Story
As an OSS maintainer, I want recent run outcomes next to issue and PR context so that triage prioritization uses current automation status.

#### Acceptance Criteria
1. Workbench rows include recent run status indicators linked to relevant run detail pages.
2. Outcome indicators refresh after kickoff and terminal run events.
3. If run status cannot be resolved, row displays unknown state with refresh guidance.

#### Verification Scenarios
```gherkin
Scenario: ST-OBS-005 happy path
  Given prerequisites for "Display recent run outcomes in workbench context rows" are satisfied
  When the actor executes the flow through "/workbench"
  Then Outcome indicators refresh after kickoff and terminal run events.

Scenario: ST-OBS-005 failure or edge path
  Given a blocking precondition exists for "Display recent run outcomes in workbench context rows"
  When the actor executes the flow through "/workbench"
  Then If run status cannot be resolved, row displays unknown state with refresh guidance.
```

#### Evidence of Done
- Workbench run indicators align with underlying run history.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-OBS-006 — Query failure context history for trend review

#### Story ID
`ST-OBS-006`

#### Title
Query failure context history for trend review

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Should

#### Primary Route/API
`/dashboard`

#### Requirement Links
R9

#### Source Spec Links
specs/02_requirements_and_scope.md, specs/30_workflow_system_overview.md

#### Dependencies
ST-WF-010

#### Story
As an OSS maintainer, I want failed run history query support so that recurring issues can be identified over time.

#### Acceptance Criteria
1. Failure history query returns error type last successful step and remediation hint fields.
2. Query supports time-window filtering for trend review workflows.
3. If query parameters are invalid, service returns typed validation error and no partial result set.

#### Verification Scenarios
```gherkin
Scenario: ST-OBS-006 happy path
  Given prerequisites for "Query failure context history for trend review" are satisfied
  When the actor executes the flow through "/dashboard"
  Then Query supports time-window filtering for trend review workflows.

Scenario: ST-OBS-006 failure or edge path
  Given a blocking precondition exists for "Query failure context history for trend review"
  When the actor executes the flow through "/dashboard"
  Then If query parameters are invalid, service returns typed validation error and no partial result set.
```

#### Evidence of Done
- Dashboard or reports can display trend slices from failure history data.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

## Story Count

- 6 stories
