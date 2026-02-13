# 05 — Workbench and Project View Stories

Atomic MVP stories for cross-project operations UX and run kickoff surfaces.

## Story Inventory

### ST-WB-001 — Render cross-project workbench inventory with issue and PR counts

#### Story ID
`ST-WB-001`

#### Title
Render cross-project workbench inventory with issue and PR counts

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/workbench`

#### Requirement Links
R13

#### Source Spec Links
specs/10_web_ui_and_routes.md, specs/ux/03_routes_and_experience_flows.md

#### Dependencies
none

#### Story
As an OSS maintainer, I want a unified workbench inventory so that I can triage maintenance work across repositories quickly.

#### Acceptance Criteria
1. `/workbench` renders all imported projects in one operational table.
2. Each project row includes open issue count open PR count and recent activity summary.
3. If workbench data fetch fails, stale-state warnings and recovery actions are displayed.

#### Verification Scenarios
```gherkin
Scenario: ST-WB-001 happy path
  Given prerequisites for "Render cross-project workbench inventory with issue and PR counts" are satisfied
  When the actor executes the flow through "/workbench"
  Then Each project row includes open issue count open PR count and recent activity summary.

Scenario: ST-WB-001 failure or edge path
  Given a blocking precondition exists for "Render cross-project workbench inventory with issue and PR counts"
  When the actor executes the flow through "/workbench"
  Then If workbench data fetch fails, stale-state warnings and recovery actions are displayed.
```

#### Evidence of Done
- Workbench table rows align with current project inventory records.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-WB-002 — Expose links from workbench rows to GitHub and project detail

#### Story ID
`ST-WB-002`

#### Title
Expose links from workbench rows to GitHub and project detail

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/workbench`

#### Requirement Links
R13

#### Source Spec Links
specs/10_web_ui_and_routes.md, specs/ux/03_routes_and_experience_flows.md

#### Dependencies
ST-WB-001

#### Story
As an OSS maintainer, I want direct links from workbench rows so that I can pivot quickly to source context.

#### Acceptance Criteria
1. Issue and PR rows include GitHub URLs and local project detail links.
2. Link targets open the correct repository issue PR or project route context.
3. If a target URL is unavailable, the row shows a disabled state with explanation instead of broken navigation.

#### Verification Scenarios
```gherkin
Scenario: ST-WB-002 happy path
  Given prerequisites for "Expose links from workbench rows to GitHub and project detail" are satisfied
  When the actor executes the flow through "/workbench"
  Then Link targets open the correct repository issue PR or project route context.

Scenario: ST-WB-002 failure or edge path
  Given a blocking precondition exists for "Expose links from workbench rows to GitHub and project detail"
  When the actor executes the flow through "/workbench"
  Then If a target URL is unavailable, the row shows a disabled state with explanation instead of broken navigation.
```

#### Evidence of Done
- Row link behavior is stable across refreshes and filters.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-WB-003 — Filter workbench data by project state and freshness

#### Story ID
`ST-WB-003`

#### Title
Filter workbench data by project state and freshness

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/workbench`

#### Requirement Links
R13

#### Source Spec Links
specs/ux/02_user_journey.md, specs/10_web_ui_and_routes.md

#### Dependencies
ST-WB-001

#### Story
As an OSS maintainer, I want workbench filters so that I can focus on urgent stale or specific project items.

#### Acceptance Criteria
1. Filters support project selection issue or PR state and freshness windows.
2. Applying filters updates visible rows without requiring route changes.
3. If filter values are invalid, defaults are restored and a typed validation notice is shown.

#### Verification Scenarios
```gherkin
Scenario: ST-WB-003 happy path
  Given prerequisites for "Filter workbench data by project state and freshness" are satisfied
  When the actor executes the flow through "/workbench"
  Then Applying filters updates visible rows without requiring route changes.

Scenario: ST-WB-003 failure or edge path
  Given a blocking precondition exists for "Filter workbench data by project state and freshness"
  When the actor executes the flow through "/workbench"
  Then If filter values are invalid, defaults are restored and a typed validation notice is shown.
```

#### Evidence of Done
- Filter chips and table content remain synchronized.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-WB-004 — Sort workbench rows by backlog and recent activity

#### Story ID
`ST-WB-004`

#### Title
Sort workbench rows by backlog and recent activity

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/workbench`

#### Requirement Links
R13

#### Source Spec Links
specs/ux/03_routes_and_experience_flows.md, specs/10_web_ui_and_routes.md

#### Dependencies
ST-WB-001

#### Story
As an OSS maintainer, I want sort controls in workbench so that I can prioritize high-impact repositories first.

#### Acceptance Criteria
1. Sort options include backlog size and recent activity ordering.
2. Selected sort order is consistently applied after data refresh events.
3. If sorting cannot be applied due to malformed data, fallback sort order is used with visible notice.

#### Verification Scenarios
```gherkin
Scenario: ST-WB-004 happy path
  Given prerequisites for "Sort workbench rows by backlog and recent activity" are satisfied
  When the actor executes the flow through "/workbench"
  Then Selected sort order is consistently applied after data refresh events.

Scenario: ST-WB-004 failure or edge path
  Given a blocking precondition exists for "Sort workbench rows by backlog and recent activity"
  When the actor executes the flow through "/workbench"
  Then If sorting cannot be applied due to malformed data, fallback sort order is used with visible notice.
```

#### Evidence of Done
- Sorted results are deterministic for repeated queries.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-WB-005 — Preserve workbench filter state when navigating to run detail and back

#### Story ID
`ST-WB-005`

#### Title
Preserve workbench filter state when navigating to run detail and back

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/workbench`

#### Requirement Links
R13

#### Source Spec Links
specs/ux/02_user_journey.md, specs/ux/03_routes_and_experience_flows.md

#### Dependencies
ST-WB-003

#### Story
As an OSS maintainer, I want navigation to preserve workbench filter state so that context is not lost during run inspection.

#### Acceptance Criteria
1. Filter and sort state persist when navigating from workbench to project or run detail pages.
2. Returning to `/workbench` restores the previous filtered view automatically.
3. If state restoration data is invalid, workbench falls back to defaults and indicates reset reason.

#### Verification Scenarios
```gherkin
Scenario: ST-WB-005 happy path
  Given prerequisites for "Preserve workbench filter state when navigating to run detail and back" are satisfied
  When the actor executes the flow through "/workbench"
  Then Returning to `/workbench` restores the previous filtered view automatically.

Scenario: ST-WB-005 failure or edge path
  Given a blocking precondition exists for "Preserve workbench filter state when navigating to run detail and back"
  When the actor executes the flow through "/workbench"
  Then If state restoration data is invalid, workbench falls back to defaults and indicates reset reason.
```

#### Evidence of Done
- Back navigation returns expected project slice without manual filter re-entry.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-WB-006 — Kick off fix workflow directly from issue or PR rows

#### Story ID
`ST-WB-006`

#### Title
Kick off fix workflow directly from issue or PR rows

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/workbench`

#### Requirement Links
R13, R5, R6

#### Source Spec Links
specs/10_web_ui_and_routes.md, specs/31_builtin_workflows.md

#### Dependencies
ST-WB-001

#### Story
As an OSS maintainer, I want row-level fix actions so that workflow kickoff does not require leaving workbench context.

#### Acceptance Criteria
1. Issue and PR rows expose quick action controls for fix-oriented workflows.
2. Quick action creates a tracked workflow run scoped to selected project and context item.
3. If kickoff validation fails, no run is created and failure details are shown inline.

#### Verification Scenarios
```gherkin
Scenario: ST-WB-006 happy path
  Given prerequisites for "Kick off fix workflow directly from issue or PR rows" are satisfied
  When the actor executes the flow through "/workbench"
  Then Quick action creates a tracked workflow run scoped to selected project and context item.

Scenario: ST-WB-006 failure or edge path
  Given a blocking precondition exists for "Kick off fix workflow directly from issue or PR rows"
  When the actor executes the flow through "/workbench"
  Then If kickoff validation fails, no run is created and failure details are shown inline.
```

#### Evidence of Done
- New run identifier is visible and linkable immediately after kickoff.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-WB-007 — Kick off issue triage workflow directly from workbench

#### Story ID
`ST-WB-007`

#### Title
Kick off issue triage workflow directly from workbench

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/workbench`

#### Requirement Links
R13, R8

#### Source Spec Links
specs/10_web_ui_and_routes.md, specs/31_builtin_workflows.md

#### Dependencies
ST-WB-001

#### Story
As an OSS maintainer, I want triage actions from workbench so that issue research automation starts from a single screen.

#### Acceptance Criteria
1. Workbench rows include triage action that starts `issue_triage` workflow with item context.
2. Kickoff path sets trigger metadata for manual launch and records initiating actor.
3. If triage action is disabled by policy, the UI communicates the blocking policy state.

#### Verification Scenarios
```gherkin
Scenario: ST-WB-007 happy path
  Given prerequisites for "Kick off issue triage workflow directly from workbench" are satisfied
  When the actor executes the flow through "/workbench"
  Then Kickoff path sets trigger metadata for manual launch and records initiating actor.

Scenario: ST-WB-007 failure or edge path
  Given a blocking precondition exists for "Kick off issue triage workflow directly from workbench"
  When the actor executes the flow through "/workbench"
  Then If triage action is disabled by policy, the UI communicates the blocking policy state.
```

#### Evidence of Done
- Run history shows manual triage launches with source row metadata.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-WB-008 — Launch workflows from project detail controls

#### Story ID
`ST-WB-008`

#### Title
Launch workflows from project detail controls

#### Persona
Solo Developer or Small Team Lead (P2)

#### Priority
MVP Must

#### Primary Route/API
`/projects/:id`

#### Requirement Links
R13, R5

#### Source Spec Links
specs/10_web_ui_and_routes.md, specs/ux/03_routes_and_experience_flows.md

#### Dependencies
none

#### Story
As a solo developer, I want project-level run controls so that I can launch workflows from repository context pages.

#### Acceptance Criteria
1. `/projects/:id` exposes workflow launch controls for supported builtin workflows.
2. Launch actions include project-specific defaults and maintain run traceability to project detail origin.
3. If project is not ready for execution, launch controls are disabled with remediation guidance.

#### Verification Scenarios
```gherkin
Scenario: ST-WB-008 happy path
  Given prerequisites for "Launch workflows from project detail controls" are satisfied
  When the actor executes the flow through "/projects/:id"
  Then Launch actions include project-specific defaults and maintain run traceability to project detail origin.

Scenario: ST-WB-008 failure or edge path
  Given a blocking precondition exists for "Launch workflows from project detail controls"
  When the actor executes the flow through "/projects/:id"
  Then If project is not ready for execution, launch controls are disabled with remediation guidance.
```

#### Evidence of Done
- Project detail and run records capture launch source attribution.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-WB-009 — Show immediate kickoff confirmation and failure states

#### Story ID
`ST-WB-009`

#### Title
Show immediate kickoff confirmation and failure states

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/workbench`

#### Requirement Links
R13, R9

#### Source Spec Links
specs/10_web_ui_and_routes.md, specs/ux/02_user_journey.md

#### Dependencies
ST-WB-006

#### Story
As an OSS maintainer, I want immediate kickoff feedback so that I can trust whether a job actually started.

#### Acceptance Criteria
1. Kickoff attempts return immediate success confirmation with run link or typed failure result.
2. Failure states include remediation guidance without removing row context from the table.
3. If network interruption occurs after kickoff request, UI resolves final run creation state explicitly.

#### Verification Scenarios
```gherkin
Scenario: ST-WB-009 happy path
  Given prerequisites for "Show immediate kickoff confirmation and failure states" are satisfied
  When the actor executes the flow through "/workbench"
  Then Failure states include remediation guidance without removing row context from the table.

Scenario: ST-WB-009 failure or edge path
  Given a blocking precondition exists for "Show immediate kickoff confirmation and failure states"
  When the actor executes the flow through "/workbench"
  Then If network interruption occurs after kickoff request, UI resolves final run creation state explicitly.
```

#### Evidence of Done
- Kickoff feedback elements are visible and testable by stable DOM IDs.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-WB-010 — Maintain searchable project inventory page

#### Story ID
`ST-WB-010`

#### Title
Maintain searchable project inventory page

#### Persona
Solo Developer or Small Team Lead (P2)

#### Priority
MVP Should

#### Primary Route/API
`/projects`

#### Requirement Links
R13, R4

#### Source Spec Links
specs/10_web_ui_and_routes.md, specs/ux/03_routes_and_experience_flows.md

#### Dependencies
none

#### Story
As a solo developer, I want searchable project inventory so that I can find and open project detail quickly.

#### Acceptance Criteria
1. `/projects` supports search and filter operations over imported project list.
2. Search results navigate to `/projects/:id` while preserving current query context.
3. If search query is invalid or empty, inventory resets to default list without error noise.

#### Verification Scenarios
```gherkin
Scenario: ST-WB-010 happy path
  Given prerequisites for "Maintain searchable project inventory page" are satisfied
  When the actor executes the flow through "/projects"
  Then Search results navigate to `/projects/:id` while preserving current query context.

Scenario: ST-WB-010 failure or edge path
  Given a blocking precondition exists for "Maintain searchable project inventory page"
  When the actor executes the flow through "/projects"
  Then If search query is invalid or empty, inventory resets to default list without error noise.
```

#### Evidence of Done
- Project inventory behavior matches imported repository metadata.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

## Story Count

- 10 stories
