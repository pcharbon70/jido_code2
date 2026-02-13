# 07 — Git Shipping and Safety Stories

Atomic MVP stories for policy-guarded branch commit push PR automation and auditability.

## Story Inventory

### ST-GIT-001 — Create run branches with deterministic naming strategy

#### Story ID
`ST-GIT-001`

#### Title
Create run branches with deterministic naming strategy

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`CommitAndPR shipping step`

#### Requirement Links
R7

#### Source Spec Links
specs/51_git_and_pr_flow.md, specs/52_git_safety_policy.md

#### Dependencies
ST-WF-006

#### Story
As an OSS maintainer, I want deterministic run branch naming so that shipping artifacts are traceable to workflow runs.

#### Acceptance Criteria
1. Shipping flow creates branches using the documented `jidocode/<workflow>/<short-run-id>` pattern.
2. Branch names are reproducible from workflow and run metadata and avoid ambiguous naming.
3. If branch creation fails, shipping halts before commit with typed branch setup error.

#### Verification Scenarios
```gherkin
Scenario: ST-GIT-001 happy path
  Given prerequisites for "Create run branches with deterministic naming strategy" are satisfied
  When the actor executes the flow through "CommitAndPR shipping step"
  Then Branch names are reproducible from workflow and run metadata and avoid ambiguous naming.

Scenario: ST-GIT-001 failure or edge path
  Given a blocking precondition exists for "Create run branches with deterministic naming strategy"
  When the actor executes the flow through "CommitAndPR shipping step"
  Then If branch creation fails, shipping halts before commit with typed branch setup error.
```

#### Evidence of Done
- Run artifacts include generated branch name and derivation metadata.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-GIT-002 — Validate workspace cleanliness before shipping actions

#### Story ID
`ST-GIT-002`

#### Title
Validate workspace cleanliness before shipping actions

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`CommitAndPR shipping step`

#### Requirement Links
R7

#### Source Spec Links
specs/52_git_safety_policy.md, specs/40_project_environments.md

#### Dependencies
ST-GIT-001

#### Story
As an OSS maintainer, I want workspace policy checks before shipping so that unintended changes are not committed.

#### Acceptance Criteria
1. Pre-ship validation checks workspace cleanliness according to environment mode policy.
2. Shipping continues only when workspace state satisfies clean-room requirements.
3. If workspace policy check fails, commit push and PR actions are blocked with remediation guidance.

#### Verification Scenarios
```gherkin
Scenario: ST-GIT-002 happy path
  Given prerequisites for "Validate workspace cleanliness before shipping actions" are satisfied
  When the actor executes the flow through "CommitAndPR shipping step"
  Then Shipping continues only when workspace state satisfies clean-room requirements.

Scenario: ST-GIT-002 failure or edge path
  Given a blocking precondition exists for "Validate workspace cleanliness before shipping actions"
  When the actor executes the flow through "CommitAndPR shipping step"
  Then If workspace policy check fails, commit push and PR actions are blocked with remediation guidance.
```

#### Evidence of Done
- Policy check result is persisted with run and step metadata.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-GIT-003 — Handle branch collisions with deterministic suffix and retry

#### Story ID
`ST-GIT-003`

#### Title
Handle branch collisions with deterministic suffix and retry

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`CommitAndPR shipping step`

#### Requirement Links
R7

#### Source Spec Links
specs/52_git_safety_policy.md, specs/51_git_and_pr_flow.md

#### Dependencies
ST-GIT-001

#### Story
As an OSS maintainer, I want branch collisions handled deterministically so that retries stay safe and predictable.

#### Acceptance Criteria
1. If target branch already exists, shipping generates deterministic suffix and retries branch setup once.
2. Collision handling avoids destructive overwrite behavior on existing remote branches.
3. If collision retry also fails, shipping terminates with typed collision failure context.

#### Verification Scenarios
```gherkin
Scenario: ST-GIT-003 happy path
  Given prerequisites for "Handle branch collisions with deterministic suffix and retry" are satisfied
  When the actor executes the flow through "CommitAndPR shipping step"
  Then Collision handling avoids destructive overwrite behavior on existing remote branches.

Scenario: ST-GIT-003 failure or edge path
  Given a blocking precondition exists for "Handle branch collisions with deterministic suffix and retry"
  When the actor executes the flow through "CommitAndPR shipping step"
  Then If collision retry also fails, shipping terminates with typed collision failure context.
```

#### Evidence of Done
- Run artifacts show collision detection and retry branch name.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-GIT-004 — Block shipping when secret scan fails

#### Story ID
`ST-GIT-004`

#### Title
Block shipping when secret scan fails

#### Persona
Security-Conscious Engineering Lead (P3)

#### Priority
MVP Must

#### Primary Route/API
`CommitAndPR shipping step`

#### Requirement Links
R7, R10

#### Source Spec Links
specs/52_git_safety_policy.md, specs/60_security_and_auth.md

#### Dependencies
ST-GIT-002

#### Story
As a security-conscious engineering lead, I want mandatory secret scan checks so that secrets are never committed or pushed.

#### Acceptance Criteria
1. Secret scan executes before commit and push operations on shipping path.
2. Any secret scan violation blocks shipping and marks run with policy_violation status.
3. If secret scan tooling errors, shipping fails closed and no commit is created.

#### Verification Scenarios
```gherkin
Scenario: ST-GIT-004 happy path
  Given prerequisites for "Block shipping when secret scan fails" are satisfied
  When the actor executes the flow through "CommitAndPR shipping step"
  Then Any secret scan violation blocks shipping and marks run with policy_violation status.

Scenario: ST-GIT-004 failure or edge path
  Given a blocking precondition exists for "Block shipping when secret scan fails"
  When the actor executes the flow through "CommitAndPR shipping step"
  Then If secret scan tooling errors, shipping fails closed and no commit is created.
```

#### Evidence of Done
- Policy check artifacts include secret scan outcome and blocked action details.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-GIT-005 — Enforce diff size thresholds before commit

#### Story ID
`ST-GIT-005`

#### Title
Enforce diff size thresholds before commit

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`CommitAndPR shipping step`

#### Requirement Links
R7

#### Source Spec Links
specs/52_git_safety_policy.md, specs/51_git_and_pr_flow.md

#### Dependencies
ST-GIT-002

#### Story
As an OSS maintainer, I want diff-size thresholds enforced so that oversized risky changes require explicit handling.

#### Acceptance Criteria
1. Pre-ship checks compute diff size and compare against project or workflow policy thresholds.
2. Changes within threshold proceed to approval and shipping flow without manual override noise.
3. If diff threshold is exceeded, shipping is blocked or escalated per policy with explicit reason.

#### Verification Scenarios
```gherkin
Scenario: ST-GIT-005 happy path
  Given prerequisites for "Enforce diff size thresholds before commit" are satisfied
  When the actor executes the flow through "CommitAndPR shipping step"
  Then Changes within threshold proceed to approval and shipping flow without manual override noise.

Scenario: ST-GIT-005 failure or edge path
  Given a blocking precondition exists for "Enforce diff size thresholds before commit"
  When the actor executes the flow through "CommitAndPR shipping step"
  Then If diff threshold is exceeded, shipping is blocked or escalated per policy with explicit reason.
```

#### Evidence of Done
- Run detail shows diff metrics and threshold policy decision.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-GIT-006 — Enforce binary file policy checks before shipping

#### Story ID
`ST-GIT-006`

#### Title
Enforce binary file policy checks before shipping

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`CommitAndPR shipping step`

#### Requirement Links
R7

#### Source Spec Links
specs/52_git_safety_policy.md, specs/51_git_and_pr_flow.md

#### Dependencies
ST-GIT-002

#### Story
As an OSS maintainer, I want binary file policy checks so that unsafe artifact changes are controlled.

#### Acceptance Criteria
1. Pre-ship policy identifies binary file additions or modifications in staged changes.
2. Shipping follows configured binary policy outcomes such as block or require escalation.
3. If binary policy evaluation fails, shipping stops with typed policy-check error.

#### Verification Scenarios
```gherkin
Scenario: ST-GIT-006 happy path
  Given prerequisites for "Enforce binary file policy checks before shipping" are satisfied
  When the actor executes the flow through "CommitAndPR shipping step"
  Then Shipping follows configured binary policy outcomes such as block or require escalation.

Scenario: ST-GIT-006 failure or edge path
  Given a blocking precondition exists for "Enforce binary file policy checks before shipping"
  When the actor executes the flow through "CommitAndPR shipping step"
  Then If binary policy evaluation fails, shipping stops with typed policy-check error.
```

#### Evidence of Done
- Policy artifacts include binary detection output and decision.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-GIT-007 — Create structured commit messages with workflow metadata trailers

#### Story ID
`ST-GIT-007`

#### Title
Create structured commit messages with workflow metadata trailers

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`CommitAndPR shipping step`

#### Requirement Links
R7

#### Source Spec Links
specs/51_git_and_pr_flow.md, specs/31_builtin_workflows.md

#### Dependencies
ST-GIT-001

#### Story
As an OSS maintainer, I want commits to follow a structured message contract so that provenance is clear in git history.

#### Acceptance Criteria
1. Commit messages follow required type summary body and workflow metadata trailer format.
2. Run metadata in commit trailers matches active workflow and run identifiers exactly.
3. If commit message generation fails contract checks, commit is blocked and error details are surfaced.

#### Verification Scenarios
```gherkin
Scenario: ST-GIT-007 happy path
  Given prerequisites for "Create structured commit messages with workflow metadata trailers" are satisfied
  When the actor executes the flow through "CommitAndPR shipping step"
  Then Run metadata in commit trailers matches active workflow and run identifiers exactly.

Scenario: ST-GIT-007 failure or edge path
  Given a blocking precondition exists for "Create structured commit messages with workflow metadata trailers"
  When the actor executes the flow through "CommitAndPR shipping step"
  Then If commit message generation fails contract checks, commit is blocked and error details are surfaced.
```

#### Evidence of Done
- Generated commits display required message sections and metadata.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-GIT-008 — Refresh GitHub auth and retry once on push auth failure

#### Story ID
`ST-GIT-008`

#### Title
Refresh GitHub auth and retry once on push auth failure

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Must

#### Primary Route/API
`CommitAndPR shipping step`

#### Requirement Links
R7, R3

#### Source Spec Links
specs/52_git_safety_policy.md, specs/50_github_integration.md

#### Dependencies
ST-GIT-007

#### Story
As an OSS maintainer, I want push auth failures to trigger one safe refresh retry so that transient credential expiry does not require manual recovery.

#### Acceptance Criteria
1. Push auth failures attempt credential refresh and one retry as documented recovery behavior.
2. Successful retry proceeds without duplicating prior git side effects.
3. If retry fails, shipping ends with typed auth failure and preserved branch artifact.

#### Verification Scenarios
```gherkin
Scenario: ST-GIT-008 happy path
  Given prerequisites for "Refresh GitHub auth and retry once on push auth failure" are satisfied
  When the actor executes the flow through "CommitAndPR shipping step"
  Then Successful retry proceeds without duplicating prior git side effects.

Scenario: ST-GIT-008 failure or edge path
  Given a blocking precondition exists for "Refresh GitHub auth and retry once on push auth failure"
  When the actor executes the flow through "CommitAndPR shipping step"
  Then If retry fails, shipping ends with typed auth failure and preserved branch artifact.
```

#### Evidence of Done
- Run logs show push attempt refresh retry sequence and final outcome.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-GIT-009 — Support dry-run shipping mode with no commit push or PR

#### Story ID
`ST-GIT-009`

#### Title
Support dry-run shipping mode with no commit push or PR

#### Persona
OSS Maintainer (P1)

#### Priority
MVP Should

#### Primary Route/API
`CommitAndPR shipping step`

#### Requirement Links
R7

#### Source Spec Links
specs/51_git_and_pr_flow.md, specs/02_requirements_and_scope.md

#### Dependencies
ST-GIT-002

#### Story
As an OSS maintainer, I want dry-run shipping mode so that I can inspect outputs without side effects.

#### Acceptance Criteria
1. Dry-run mode executes diff and report generation but skips commit push and PR actions.
2. Dry-run outputs are persisted as artifacts for review and approval context.
3. If dry-run mode is requested with incompatible policy, the request is rejected with typed validation guidance.

#### Verification Scenarios
```gherkin
Scenario: ST-GIT-009 happy path
  Given prerequisites for "Support dry-run shipping mode with no commit push or PR" are satisfied
  When the actor executes the flow through "CommitAndPR shipping step"
  Then Dry-run outputs are persisted as artifacts for review and approval context.

Scenario: ST-GIT-009 failure or edge path
  Given a blocking precondition exists for "Support dry-run shipping mode with no commit push or PR"
  When the actor executes the flow through "CommitAndPR shipping step"
  Then If dry-run mode is requested with incompatible policy, the request is rejected with typed validation guidance.
```

#### Evidence of Done
- Run artifacts clearly indicate dry-run execution and suppressed side effects.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

### ST-GIT-010 — Persist git side-effect audit metadata for every shipping action

#### Story ID
`ST-GIT-010`

#### Title
Persist git side-effect audit metadata for every shipping action

#### Persona
Security-Conscious Engineering Lead (P3)

#### Priority
MVP Must

#### Primary Route/API
`CommitAndPR shipping step`

#### Requirement Links
R7, R9, R10

#### Source Spec Links
specs/52_git_safety_policy.md, specs/60_security_and_auth.md

#### Dependencies
ST-GIT-001

#### Story
As a security-conscious engineering lead, I want git side effects audited so that compliance and incident analysis are possible.

#### Acceptance Criteria
1. Each git side effect stores command intent result code actor workflow run identifier and timestamp.
2. Policy-check outcomes are attached to audit records for commit push and PR actions.
3. If audit persistence fails, shipping action fails and no silent side effect is accepted.

#### Verification Scenarios
```gherkin
Scenario: ST-GIT-010 happy path
  Given prerequisites for "Persist git side-effect audit metadata for every shipping action" are satisfied
  When the actor executes the flow through "CommitAndPR shipping step"
  Then Policy-check outcomes are attached to audit records for commit push and PR actions.

Scenario: ST-GIT-010 failure or edge path
  Given a blocking precondition exists for "Persist git side-effect audit metadata for every shipping action"
  When the actor executes the flow through "CommitAndPR shipping step"
  Then If audit persistence fails, shipping action fails and no silent side effect is accepted.
```

#### Evidence of Done
- Audit views expose complete side-effect record lineage per run.
- A matching traceability row exists in `specs/stories/00_traceability_matrix.md`.

## Story Count

- 10 stories
