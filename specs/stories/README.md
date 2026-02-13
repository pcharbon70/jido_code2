# Story Backlog (MVP)

This folder is the detailed implementation backlog for JidoCode MVP.

## Source of Truth

- `specs/stories/` is the canonical implementation story backlog.
- `specs/ux/04_user_stories.md` remains a high-level summary and crosswalk.

## Story Card Schema (Required)

Every story in this folder includes these exact sections:

1. `Story ID`
2. `Title`
3. `Persona`
4. `Priority`
5. `Primary Route/API`
6. `Requirement Links`
7. `Source Spec Links`
8. `Dependencies`
9. `Story`
10. `Acceptance Criteria`
11. `Verification Scenarios`
12. `Evidence of Done`

## Conventions

- Story ID pattern: `ST-<DOMAIN>-<NNN>`.
- Scope: MVP only.
- Priority values: `MVP Must`, `MVP Should`.
- Dependencies are explicit: `none` or specific story IDs.
- Every story includes at least one happy-path and one failure/edge scenario.

## Domain Files

| File | Domain | Story IDs | Count |
|---|---|---|---|
| `01_onboarding_bootstrap.md` | Onboarding and bootstrap | `ST-ONB-001..010` | 10 |
| `02_auth_and_access.md` | Auth and access control | `ST-AUTH-001..008` | 8 |
| `03_secrets_and_provider_credentials.md` | Secret and provider lifecycle | `ST-SEC-001..010` | 10 |
| `04_github_integration_and_repo_import.md` | GitHub integration and import | `ST-GH-001..010` | 10 |
| `05_workbench_and_project_views.md` | Workbench and project UX | `ST-WB-001..010` | 10 |
| `06_workflow_runtime_and_approvals.md` | Workflow runtime and approvals | `ST-WF-001..010` | 10 |
| `07_git_shipping_and_safety.md` | Git shipping and safety policy | `ST-GIT-001..010` | 10 |
| `08_issue_bot_and_agent_controls.md` | Issue Bot and support-agent controls | `ST-BOT-001..008` | 8 |
| `09_observability_and_artifacts.md` | Observability and artifacts | `ST-OBS-001..006` | 6 |
| `10_rpc_and_typescript_client.md` | RPC and TypeScript client | `ST-RPC-001..008` | 8 |
| `11_deployment_and_environment_modes.md` | Deployment and environment modes | `ST-DEP-001..008` | 8 |
| `12_security_runbooks_and_incidents.md` | Security runbooks and incident response | `ST-SIR-001..008` | 8 |

Total: **106 stories**

## Verification Commands

```bash
# story heading count
rg -n "^### ST-" specs/stories/*.md | wc -l

# traceability rows (excluding header)
rg -n "^\| `ST-" specs/stories/00_traceability_matrix.md | wc -l

# each story has required sections
for s in "Story ID" "Title" "Persona" "Priority" "Primary Route/API" "Requirement Links" \
         "Source Spec Links" "Dependencies" "Story" "Acceptance Criteria" \
         "Verification Scenarios" "Evidence of Done"; do
  echo "$s: $(rg -n "^#### ${s}$" specs/stories/*.md | wc -l)"
done
```
