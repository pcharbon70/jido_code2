# 06 — Workflow Runtime and Approval Stories

Atomic MVP stories for run lifecycle, event streaming, approval gates, and retry semantics.

## Story Inventory

### ST-WF-001 — Start manual workflow runs from UI contexts

#### Story ID
`ST-WF-001`

#### Title
Start manual workflow runs from UI contexts

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/workflows`

#### Requirement Links
R5, R6, R13

#### Source Spec Links
specs/30_workflow_system_overview.md, specs/31_builtin_workflows.md

#### Dependencies
ST-WB-006

#### Story
As an OSS maintainer, I want manual workflow launches from UI surfaces so that automation begins with explicit operator intent.

#### Acceptance Criteria
1. Starting a workflow creates a `WorkflowRun` with project trigger and input metadata.
2. Run creation returns a stable run identifier and navigable detail route.
3. If required inputs are missing, run creation fails with typed validation errors and no partial run state.

#### Verification Scenarios
```gherkin
Scenario: ST-WF-001 happy path
  Given prerequisites for "Start manual workflow runs from UI contexts" are satisfied
  When the actor executes the flow through "/workflows"
  Then Run creation returns a stable run identifier and navigable detail route.

Scenario: ST-WF-001 failure or edge path
  Given a blocking precondition exists for "Start manual workflow runs from UI contexts"
  When the actor executes the flow through "/workflows"
  Then If required inputs are missing, run creation fails with typed validation errors and no partial run state.
```

#### Evidence of Done
- Run list and detail routes display newly created runs immediately.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-WF-002 — Pin workflow definition version at run creation

#### Story ID
`ST-WF-002`

#### Title
Pin workflow definition version at run creation

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/projects/:id/runs/:run_id`

#### Requirement Links
R5

#### Source Spec Links
specs/30_workflow_system_overview.md, specs/31_builtin_workflows.md

#### Dependencies
ST-WF-001

#### Story
As an OSS maintainer, I want each run to pin workflow version so that execution remains reproducible after definition updates.

#### Acceptance Criteria
1. Run creation stores workflow name and version used for that execution instance.
2. Subsequent workflow definition changes do not alter already-started run behavior.
3. If version pinning data cannot be recorded, run creation is aborted safely.

#### Verification Scenarios
```gherkin
Scenario: ST-WF-002 happy path
  Given prerequisites for "Pin workflow definition version at run creation" are satisfied
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then Subsequent workflow definition changes do not alter already-started run behavior.

Scenario: ST-WF-002 failure or edge path
  Given a blocking precondition exists for "Pin workflow definition version at run creation"
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then If version pinning data cannot be recorded, run creation is aborted safely.
```

#### Evidence of Done
- Run detail metadata shows pinned workflow version.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-WF-003 — Persist run status lifecycle transitions

#### Story ID
`ST-WF-003`

#### Title
Persist run status lifecycle transitions

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/projects/:id/runs/:run_id`

#### Requirement Links
R5, R9

#### Source Spec Links
specs/30_workflow_system_overview.md, specs/20_ash_domain_model.md

#### Dependencies
ST-WF-001

#### Story
As an OSS maintainer, I want durable status transitions so that run progress survives restarts and can be audited.

#### Acceptance Criteria
1. Run status follows allowed lifecycle transitions for pending running awaiting_approval completed failed cancelled.
2. Each transition is persisted with timestamps and current step context.
3. If an invalid transition is requested, the transition is rejected and run state remains unchanged.

#### Verification Scenarios
```gherkin
Scenario: ST-WF-003 happy path
  Given prerequisites for "Persist run status lifecycle transitions" are satisfied
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then Each transition is persisted with timestamps and current step context.

Scenario: ST-WF-003 failure or edge path
  Given a blocking precondition exists for "Persist run status lifecycle transitions"
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then If an invalid transition is requested, the transition is rejected and run state remains unchanged.
```

#### Evidence of Done
- Run timeline view reflects persisted transition history accurately.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-WF-004 — Publish required run events on the run topic

#### Story ID
`ST-WF-004`

#### Title
Publish required run events on the run topic

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`jido_code:run:<run_id>`

#### Requirement Links
R5, R9

#### Source Spec Links
specs/30_workflow_system_overview.md, specs/41_forge_integration.md

#### Dependencies
ST-WF-003

#### Story
As an OSS maintainer, I want required run events published consistently so that real-time UI and diagnostics remain reliable.

#### Acceptance Criteria
1. Run topic emits required events including step transitions approvals and terminal state events.
2. Each event payload includes run_id workflow_name workflow_version timestamp and correlation_id.
3. If event publication fails, failure is captured with typed event-channel diagnostics.

#### Verification Scenarios
```gherkin
Scenario: ST-WF-004 happy path
  Given prerequisites for "Publish required run events on the run topic" are satisfied
  When the actor executes the flow through "jido_code:run:<run_id>"
  Then Each event payload includes run_id workflow_name workflow_version timestamp and correlation_id.

Scenario: ST-WF-004 failure or edge path
  Given a blocking precondition exists for "Publish required run events on the run topic"
  When the actor executes the flow through "jido_code:run:<run_id>"
  Then If event publication fails, failure is captured with typed event-channel diagnostics.
```

#### Evidence of Done
- Event stream inspection shows complete required event sequence for representative runs.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-WF-005 — Render approval request payload with diff test and risk summaries

#### Story ID
`ST-WF-005`

#### Title
Render approval request payload with diff test and risk summaries

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/projects/:id/runs/:run_id`

#### Requirement Links
R5, R7

#### Source Spec Links
specs/30_workflow_system_overview.md, specs/51_git_and_pr_flow.md

#### Dependencies
ST-WF-003

#### Story
As an OSS maintainer, I want rich approval payload context so that ship decisions are informed and safe.

#### Acceptance Criteria
1. Runs entering `awaiting_approval` include diff summary test summary and risk notes in approval context.
2. Approval context is visible in run detail before approve or reject actions are enabled.
3. If approval context generation fails, run remains blocked with explicit remediation guidance.

#### Verification Scenarios
```gherkin
Scenario: ST-WF-005 happy path
  Given prerequisites for "Render approval request payload with diff test and risk summaries" are satisfied
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then Approval context is visible in run detail before approve or reject actions are enabled.

Scenario: ST-WF-005 failure or edge path
  Given a blocking precondition exists for "Render approval request payload with diff test and risk summaries"
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then If approval context generation fails, run remains blocked with explicit remediation guidance.
```

#### Evidence of Done
- Approval panel displays complete context payload for each gated run.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-WF-006 — Continue run execution after explicit approval

#### Story ID
`ST-WF-006`

#### Title
Continue run execution after explicit approval

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/projects/:id/runs/:run_id`

#### Requirement Links
R5, R7

#### Source Spec Links
specs/30_workflow_system_overview.md, specs/31_builtin_workflows.md

#### Dependencies
ST-WF-005

#### Story
As an OSS maintainer, I want approved runs to resume automatically so that shipping steps proceed without manual orchestration.

#### Acceptance Criteria
1. Approve action transitions run from awaiting_approval back to running and resumes next step execution.
2. Approval decision is audited with actor and timestamp metadata.
3. If approve action cannot be applied, run remains awaiting_approval and reports typed action failure.

#### Verification Scenarios
```gherkin
Scenario: ST-WF-006 happy path
  Given prerequisites for "Continue run execution after explicit approval" are satisfied
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then Approval decision is audited with actor and timestamp metadata.

Scenario: ST-WF-006 failure or edge path
  Given a blocking precondition exists for "Continue run execution after explicit approval"
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then If approve action cannot be applied, run remains awaiting_approval and reports typed action failure.
```

#### Evidence of Done
- Run timeline shows approval_granted event followed by resumed step events.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-WF-007 — Cancel or route run on rejection according to policy

#### Story ID
`ST-WF-007`

#### Title
Cancel or route run on rejection according to policy

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/projects/:id/runs/:run_id`

#### Requirement Links
R5

#### Source Spec Links
specs/30_workflow_system_overview.md, specs/31_builtin_workflows.md

#### Dependencies
ST-WF-005

#### Story
As an OSS maintainer, I want reject behavior to follow workflow policy so that undesired changes do not ship.

#### Acceptance Criteria
1. Reject action transitions run to cancelled or configured retry route according to workflow definition.
2. Rejection metadata is persisted with actor rationale and timestamp where provided.
3. If rejection processing fails, run state remains unchanged and user receives typed retry guidance.

#### Verification Scenarios
```gherkin
Scenario: ST-WF-007 happy path
  Given prerequisites for "Cancel or route run on rejection according to policy" are satisfied
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then Rejection metadata is persisted with actor rationale and timestamp where provided.

Scenario: ST-WF-007 failure or edge path
  Given a blocking precondition exists for "Cancel or route run on rejection according to policy"
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then If rejection processing fails, run state remains unchanged and user receives typed retry guidance.
```

#### Evidence of Done
- Run detail shows approval_rejected event and resulting terminal or reroute state.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-WF-008 — Support full-run retry while preserving prior artifacts

#### Story ID
`ST-WF-008`

#### Title
Support full-run retry while preserving prior artifacts

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/projects/:id/runs/:run_id`

#### Requirement Links
R5, R9

#### Source Spec Links
specs/30_workflow_system_overview.md, specs/02_requirements_and_scope.md

#### Dependencies
ST-WF-003

#### Story
As an OSS maintainer, I want full-run retry semantics so that recoverable failures can be re-executed safely.

#### Acceptance Criteria
1. Retry action creates a new run attempt according to full-run retry default policy.
2. Prior failure artifacts and typed reasons remain linked and queryable after retry starts.
3. If retry is disallowed by policy, action is blocked with typed policy violation details.

#### Verification Scenarios
```gherkin
Scenario: ST-WF-008 happy path
  Given prerequisites for "Support full-run retry while preserving prior artifacts" are satisfied
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then Prior failure artifacts and typed reasons remain linked and queryable after retry starts.

Scenario: ST-WF-008 failure or edge path
  Given a blocking precondition exists for "Support full-run retry while preserving prior artifacts"
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then If retry is disallowed by policy, action is blocked with typed policy violation details.
```

#### Evidence of Done
- Run history shows parent failure and retry relationship with preserved artifacts.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-WF-009 — Allow step-level retry only when contract explicitly permits

#### Story ID
`ST-WF-009`

#### Title
Allow step-level retry only when contract explicitly permits

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Should

#### Primary Route/API
`/projects/:id/runs/:run_id`

#### Requirement Links
R5

#### Source Spec Links
specs/30_workflow_system_overview.md, specs/31_builtin_workflows.md

#### Dependencies
ST-WF-008

#### Story
As an OSS maintainer, I want step-level retry constrained by workflow contract so that unsafe partial reruns are prevented.

#### Acceptance Criteria
1. Step-level retry controls appear only for workflows that declare step retry capability.
2. Executing a permitted step retry preserves run audit and artifact lineage.
3. If step-level retry is not declared, the UI and API reject the operation with clear guidance.

#### Verification Scenarios
```gherkin
Scenario: ST-WF-009 happy path
  Given prerequisites for "Allow step-level retry only when contract explicitly permits" are satisfied
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then Executing a permitted step retry preserves run audit and artifact lineage.

Scenario: ST-WF-009 failure or edge path
  Given a blocking precondition exists for "Allow step-level retry only when contract explicitly permits"
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then If step-level retry is not declared, the UI and API reject the operation with clear guidance.
```

#### Evidence of Done
- Retry controls and behavior align with workflow contract metadata.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-WF-010 — Expose typed failure context with remediation hint

#### Story ID
`ST-WF-010`

#### Title
Expose typed failure context with remediation hint

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`/projects/:id/runs/:run_id`

#### Requirement Links
R5, R9

#### Source Spec Links
specs/30_workflow_system_overview.md, specs/02_requirements_and_scope.md

#### Dependencies
ST-WF-003

#### Story
As an OSS maintainer, I want failed runs to include typed context and next steps so that recovery is fast and consistent.

#### Acceptance Criteria
1. Failed runs persist error type last successful step and remediation hint metadata.
2. Failure details are visible in run detail and available to query for postmortem analysis.
3. If failure context cannot be assembled fully, run still captures minimal typed reason and indicates missing fields.

#### Verification Scenarios
```gherkin
Scenario: ST-WF-010 happy path
  Given prerequisites for "Expose typed failure context with remediation hint" are satisfied
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then Failure details are visible in run detail and available to query for postmortem analysis.

Scenario: ST-WF-010 failure or edge path
  Given a blocking precondition exists for "Expose typed failure context with remediation hint"
  When the actor executes the flow through "/projects/:id/runs/:run_id"
  Then If failure context cannot be assembled fully, run still captures minimal typed reason and indicates missing fields.
```

#### Evidence of Done
- Run failure views include standardized context fields for all terminal failures.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

## Story Count

- 10 stories
