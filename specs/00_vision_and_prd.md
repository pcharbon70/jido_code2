# 00 — Vision & PRD

## Vision

JidoCode is an open-source, self-hosted coding orchestration product that turns engineering tasks and GitHub events into safe, reviewable pull requests.

The product is built on Jido, Runic, and Forge, but the priority is practical software delivery: durable workflows, approval gates, observability, and reliable git/PR automation.

## Product Identity

- Canonical name: **JidoCode**
- Category: single-user coding orchestrator
- Primary deployment: cloud VM (Fly Machine style)
- Secondary mode: local dev/fallback self-host
- Future mode: local desktop packaging (Tauri-style)

## Why Open Source

- Users can audit orchestration and safety logic
- Community can extend workflows, agents, and integrations
- The implementation serves as a reference for Jido ecosystem usage
- Users keep control of their own credentials and infrastructure

## Target Users

### Primary

Solo developers and small team leads who manage a few repositories and want repeatable automation for implementation, test repair, and issue handling.

### Secondary

Open-source maintainers who need triage automation and guarded PR generation.

## Primary Jobs-to-be-Done

1. Run a coding task end-to-end and get a PR.
2. Fix failing tests via guided workflow automation.
3. Triage and respond to GitHub issues using support agents.
4. Observe live workflow execution and enforce human approval before shipping.

## Core Product Principles

| Principle | Meaning |
|---|---|
| Durable execution | Workflow state survives restarts and preserves provenance |
| Safe delivery | Git safety checks and approval gates before code ships |
| Auditable operations | Every run, transition, and side effect is trackable |
| Cloud-first pragmatism | Production path is straightforward and documented |
| Typed interfaces | Public product actions are callable via generated TypeScript RPC |
| Single-user clarity | Security and auth optimized for one owner, not multi-tenant complexity |

## Key Differentiators

| Typical chat coding tool | JidoCode |
|---|---|
| Ephemeral session | Durable workflow runs |
| Manual git + PR | Automated and policy-guarded git + PR |
| Minimal run visibility | Real-time run timeline + artifacts |
| Weak operational controls | Explicit security and git safety policies |
| Prompt-only interaction | Workflow + webhook trigger model (including Issue Bot) |

## Success Metrics

| Metric | Target |
|---|---|
| Deploy to first successful workflow run | < 15 minutes |
| Workflow completion to PR creation | < 30 seconds |
| Successful run rate (non-crash) | > 95% |
| Issue bot webhook-to-response latency (P95) | < 2 minutes |
| Public action RPC coverage | 100% of required product action inventory |

## Release Phases

### Phase 1 (MVP)

- Owner onboarding and configuration
- AshAuth single-user setup
- Encrypted DB secrets + env bootstrap
- Cloud VM deployment guidance (local dev supported)
- Repo import and workspace provisioning
- Builtin workflows:
  - Implement Task
  - Fix Failing Tests
  - Issue Triage & Research (webhook-triggered)
- Approval gates and live observability
- Safe branch/commit/push/PR pipeline
- Full product action coverage in TypeScript RPC

### Phase 2

- Expanded model routing and cost controls
- Sprite-first scaling enhancements
- Advanced multi-phase research/design workflows
- Broader support-agent library
- Tighter operational analytics

### Phase 3

- Visual workflow authoring UX
- Template library and scheduling
- Desktop deployment package (Tauri-style)
- Advanced policy and governance tooling

## Ecosystem Dependencies

| Package | Role |
|---|---|
| `jido`, `jido_action`, `jido_signal` | Agent runtime and messaging |
| `jido_runic` | Durable workflow DAG execution |
| `ash`, `ash_postgres` | Data model and persistence |
| `ash_authentication` | Single-user auth architecture |
| `ash_cloak`, `cloak` | Encrypted secret persistence |
| `ash_typescript` | Typed RPC generation |
| `req`, `req_llm` | HTTP and LLM integrations |
| `sprites` | Cloud sandbox execution |
