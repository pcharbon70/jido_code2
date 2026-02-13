# 02 — Requirements & Scope

## Hard Requirements

### R1: Single-User AshAuth

- JidoCode serves one owner account per instance.
- Auth is AshAuthentication-based.
- Browser access uses session auth.
- API clients can use API key or bearer token auth.
- Open registration is disabled by default in production.

### R2: Onboarding and Owner Bootstrap

- First-run onboarding initializes owner access, secrets, providers, and project defaults.
- Owner bootstrap flow is explicit and recoverable.
- Setup state is persisted and resumable.

### R3: GitHub App Integration

- User provides GitHub App credentials.
- App installation and webhook wiring are validated.
- Repository import and webhook processing are supported.

### R4: Project Import and Environments

- Repositories can be imported and prepared for workflow execution.
- Cloud-first environment defaults are supported.
- Local dev/fallback mode remains supported.

### R5: Durable Workflow Orchestration

- Workflows are durable Runic DAGs.
- Workflow versions are pinned per run.
- Approval gates and retry semantics are explicit.

### R6: AI Coding Agent Execution

- Claude Code runner is MVP baseline.
- Workflow steps can invoke Forge-backed execution and LLM-only actions.
- Observability and artifact capture are mandatory.

### R7: Git + PR Shipping

- Successful workflows can create branch, commit, push, and open PR.
- All shipping paths enforce git safety policy checks.
- Failure reasons are captured with actionable status.

### R8: Support Agents in MVP (Issue Bot)

- GitHub Issue Bot is MVP scope.
- Issue bot can trigger from webhook events.
- Per-project configuration and approval policy are supported.

### R9: Real-Time Observability

- Live status, logs, step transitions, and artifacts stream to UI.
- Run history and failure context are persisted.

### R10: Secure Secret Handling

- DB-stored secrets are encrypted at rest.
- Env vars are accepted as bootstrap/runtime secret sources.
- Redaction is enforced across logs, PubSub, artifacts, and prompts.

### R11: Cloud VM First Deployment

- Production path targets Fly-style cloud VM deployment.
- Local mode remains supported for development and fallback.
- Future Tauri local app packaging is documented as forward plan.

### R12: Full TypeScript RPC via Ash

- Product action inventory is defined and normative.
- Each required public action is callable via `/rpc/run` and `/rpc/validate`.
- Generated `assets/js/ash_rpc.ts` must remain complete for that inventory.

### R13: Cross-Project OSS Workbench

- MVP includes a cross-project UI view of all imported repositories.
- Workbench shows issue and PR context for each project.
- Workbench supports launching agent jobs directly from issue/PR context.
- Workbench must link to run details and reflect kickoff outcome.

## MVP Scope (Phase 1)

### In Scope

- [ ] Owner bootstrap onboarding (AshAuth single-user)
- [ ] GitHub App setup + webhook verification
- [ ] Encrypted secret storage strategy and redaction pipeline
- [ ] Repo import and workspace setup
- [ ] Cloud VM deployment baseline docs
- [ ] Local dev/fallback mode support
- [ ] Builtin workflows:
  - [ ] Implement Task
  - [ ] Fix Failing Tests
  - [ ] Issue Triage & Research (webhook-triggered)
- [ ] Approval gates
- [ ] Git/PR automation with safety checks
- [ ] Run timeline + streaming output
- [ ] Cross-project workbench with issue/PR visibility and agent kickoff actions
- [ ] Product-domain TypeScript RPC completeness

### Out of Scope (Phase 1)

- Visual workflow builder
- Scheduled workflows
- Multi-repo workflows
- Marketplace/template exchange
- Desktop packaging implementation (Tauri)
- Broad support-agent ecosystem beyond Issue Bot

## Non-Goals

1. Multi-tenant SaaS architecture
2. IDE plugin product mode
3. General-purpose non-coding agent platform
4. Secrets persisted in plaintext DB fields

## Technical Constraints

| Constraint | Requirement |
|---|---|
| Runtime | Elixir/OTP, Phoenix 1.8 |
| Persistence | PostgreSQL + Ash |
| Auth | AshAuthentication single-user policy |
| Secret encryption | `ash_cloak` + `cloak` |
| API surface | Ash + TypeScript RPC |
| Workflow engine | `jido_runic` |
| Execution | Forge + Sprites/local workspace |
| GitHub calls | `Req` |
| UI | Phoenix LiveView |

## Acceptance Matrix (MVP)

| Area | Acceptance Criteria |
|---|---|
| Auth | Owner can sign in; open registration is disabled in production |
| Issue Bot | `issues.opened` webhook can produce tracked workflow run |
| Secrets | No plaintext secret fields in DB model specs |
| Deployment | Cloud VM path is complete and operationally documented |
| Git Safety | Commit/push blocked when mandatory checks fail |
| Workbench | User can view all projects + issue/PR state and launch tracked agent jobs |
| RPC | 100% of required product actions have typed RPC run/validate coverage |
