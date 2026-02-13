# 04 — User Stories (Summary)

This file is the high-level user story summary for UX planning.

Detailed implementation-grade stories now live in `specs/stories/`.

## Detailed Backlog Reference

- Index and schema: `../stories/README.md`
- Requirement and route crosswalk: `../stories/00_traceability_matrix.md`

## Epic Summary (MVP)

| Epic | Focus | Detailed Story File | Story IDs | Count |
|---|---|---|---|---|
| A | Onboarding and owner bootstrap | `../stories/01_onboarding_bootstrap.md` | `ST-ONB-001..010` | 10 |
| B | Auth and access controls | `../stories/02_auth_and_access.md` | `ST-AUTH-001..008` | 8 |
| C | Secrets and provider credentials | `../stories/03_secrets_and_provider_credentials.md` | `ST-SEC-001..010` | 10 |
| D | GitHub integration and repo import | `../stories/04_github_integration_and_repo_import.md` | `ST-GH-001..010` | 10 |
| E | Workbench and project views | `../stories/05_workbench_and_project_views.md` | `ST-WB-001..010` | 10 |
| F | Workflow runtime and approvals | `../stories/06_workflow_runtime_and_approvals.md` | `ST-WF-001..010` | 10 |
| G | Git shipping and safety | `../stories/07_git_shipping_and_safety.md` | `ST-GIT-001..010` | 10 |
| H | Issue Bot and agent controls | `../stories/08_issue_bot_and_agent_controls.md` | `ST-BOT-001..008` | 8 |
| I | Observability and artifacts | `../stories/09_observability_and_artifacts.md` | `ST-OBS-001..006` | 6 |
| J | RPC and TypeScript client | `../stories/10_rpc_and_typescript_client.md` | `ST-RPC-001..008` | 8 |
| K | Deployment and environment modes | `../stories/11_deployment_and_environment_modes.md` | `ST-DEP-001..008` | 8 |
| L | Security runbooks and incidents | `../stories/12_security_runbooks_and_incidents.md` | `ST-SIR-001..008` | 8 |

Total: **106 MVP stories**

## Priority Summary

### MVP Must

- All `ST-ONB-*`, `ST-AUTH-*` except `ST-AUTH-008`
- All `ST-SEC-*` except `ST-SEC-008`
- All `ST-GH-*` except `ST-GH-002` and `ST-GH-009`
- All `ST-WB-*` except `ST-WB-010`
- All `ST-WF-*` except `ST-WF-009`
- All `ST-GIT-*` except `ST-GIT-009`
- All `ST-BOT-*` except `ST-BOT-006`
- All `ST-OBS-*` except `ST-OBS-006`
- All `ST-RPC-*` except `ST-RPC-007` and `ST-RPC-008`
- All `ST-DEP-*`
- All `ST-SIR-*` except `ST-SIR-008`

### MVP Should

- `ST-AUTH-008`
- `ST-SEC-008`
- `ST-GH-002`, `ST-GH-009`
- `ST-WB-010`
- `ST-WF-009`
- `ST-GIT-009`
- `ST-BOT-006`
- `ST-OBS-006`
- `ST-RPC-007`, `ST-RPC-008`
- `ST-SIR-008`

## Story Quality Rules

Detailed stories in `specs/stories/` are intentionally atomic and include:

1. explicit dependency declaration (`none` or story IDs)
2. objective acceptance criteria
3. happy-path and failure/edge verification scenarios
4. requirement and source-spec traceability
