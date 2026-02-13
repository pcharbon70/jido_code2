# JidoCode — PRD & Specification Index

**JidoCode** is an open-source, self-hosted coding orchestrator built on the Jido ecosystem. It runs durable workflow pipelines that turn prompts, issues, and coding tasks into reviewed pull requests with full observability, strict safety controls, and typed API access.

JidoCode is **product-first**: practical day-to-day coding automation is the primary goal. Showing Jido ecosystem capabilities is a secondary outcome.

## Product Positioning

- Primary deployment target: **cloud VM** (Fly Machine style)
- Secondary mode: **local development/self-host fallback**
- Future mode: **local desktop packaging** (Tauri-style)

## MVP User Journey

```text
1. Deploy JidoCode on cloud VM
2. Complete onboarding (owner account, secrets, GitHub App)
3. Import repository and select environment
4. Run builtin workflow (implement task, fix failing tests, or issue triage)
5. Review output and approval gates
6. Auto-create branch, commit, push, and pull request
```

## Specs Index

| # | Document | Status | Description |
|---|---|---|---|
| 00 | [Vision & PRD](00_vision_and_prd.md) | Draft | Product vision and release phases |
| 01 | [Glossary & Concepts](01_glossary_and_concepts.md) | Draft | Canonical terminology |
| 02 | [Requirements & Scope](02_requirements_and_scope.md) | Draft | Hard requirements and phased scope |
| 03 | [Decisions & Invariants](03_decisions_and_invariants.md) | Draft | Cross-spec source of truth |
| 10 | [Web UI & Routes](10_web_ui_and_routes.md) | Draft | LiveView information architecture |
| 11 | [Onboarding Flow](11_onboarding_flow.md) | Draft | First-run setup and owner bootstrap |
| 20 | [Ash Domain Model](20_ash_domain_model.md) | Draft | Resource model and secret classifications |
| 30 | [Workflow System](30_workflow_system_overview.md) | Draft | Runic orchestration model |
| 31 | [Builtin Workflows](31_builtin_workflows.md) | Draft | MVP and phase-tagged workflows |
| 32 | [Agent & Action Catalog](32_agent_and_action_catalog.md) | Draft | Agent/action contracts |
| 40 | [Project Environments](40_project_environments.md) | Draft | Cloud-first workspace model |
| 41 | [Forge Integration](41_forge_integration.md) | Draft | Session lifecycle and execution mapping |
| 50 | [GitHub Integration](50_github_integration.md) | Draft | App auth, webhooks, repo import |
| 51 | [Git & PR Flow](51_git_and_pr_flow.md) | Draft | Happy-path shipping flow |
| 52 | [Git Safety Policy](52_git_safety_policy.md) | Draft | Guardrails, checks, recovery, auditability |
| 60 | [Security & Auth](60_security_and_auth.md) | Draft | AshAuth single-user security model |
| 61 | [Configuration & Deployment](61_configuration_and_deployment.md) | Draft | Cloud VM-first ops model |
| 62 | [Security Playbook](62_security_playbook.md) | Draft | Operational security runbooks |
| UX | [UX Spec Pack](ux/README.md) | Draft | Personas, journeys, routes, and user stories |
| — | [Forge Overview](FORGE_OVERVIEW.md) | Reference | Implementation-level Forge details |

## Canonical Invariants

The following are normative and must stay consistent across all specs:

1. Product name is **`JidoCode`**.
2. MVP includes **GitHub Issue Bot** with webhook-triggered execution.
3. Auth uses **AshAuthentication** in single-user mode.
4. Secrets can be stored in DB **only when encrypted**; env vars are bootstrap/runtime sources.
5. Cloud VM deployment is primary; local mode is supported for dev/fallback.
6. TypeScript RPC via Ash is required for all product-domain public actions.
7. `specs/current_status.md` is removed and not used as a planning artifact.

## Reading Order

1. `00` → `02` → `03` for strategic and normative context
2. `20` for data model contracts
3. `30`/`31`/`32` for workflow and runtime behavior
4. `40`/`41`/`50`/`51`/`52` for execution and delivery flows
5. `60`/`61`/`62` for security and operations

## Maintenance Rule

Any cross-cutting change (auth, secrets, deployment, naming, API surface) must update:

- `03_decisions_and_invariants.md`
- all impacted spec sections in this index
- acceptance criteria in `02_requirements_and_scope.md`
