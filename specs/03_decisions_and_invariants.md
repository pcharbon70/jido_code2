# 03 — Decisions & Invariants

This document is the cross-spec source of truth for decisions that affect multiple parts of JidoCode.

## Locked Decisions

| ID | Decision | Status | Effective Scope |
|---|---|---|---|
| D1 | Product name is `JidoCode` | Locked | All UI, docs, APIs, artifacts |
| D2 | MVP includes GitHub Issue Bot (webhook-triggered) | Locked | Requirements, workflows, GitHub integration |
| D3 | Auth model is AshAuthentication single-user mode | Locked | Web routes, onboarding, API auth |
| D4 | DB secrets allowed only with encryption (`ash_cloak`/Cloak) | Locked | Data model, security, deployment |
| D5 | Deployment is cloud VM first (Fly-style) | Locked | Ops, onboarding, defaults |
| D6 | Local mode supported for dev/fallback | Locked | Config and workspace docs |
| D7 | Future local desktop mode via Tauri-style packaging | Planned | Deployment roadmap |
| D8 | Full TypeScript RPC API via Ash for product actions | Locked | API contracts, generated TS client |
| D9 | Git safety policy is mandatory and centralized in spec 52 | Locked | Git flow and workflow actions |
| D10 | `specs/current_status.md` is removed | Locked | Spec governance |

## Product Invariants

1. JidoCode is a single-user orchestration product, not a multi-tenant SaaS.
2. No secret value is stored unencrypted at rest in Postgres.
3. Every workflow that can ship code must pass git safety checks before commit/push/PR.
4. Webhook processing is authenticated and idempotent.
5. Every product-domain public action required by UI or automation has typed RPC exposure.
6. Cloud-first defaults must not break local developer workflows.

## Auth Invariant (Single-User AshAuth)

- A single owner account controls the instance.
- Session-based auth is used for browser UI.
- API key and bearer token auth are supported for API clients.
- Open registration is disabled in production by default.
- Owner bootstrap exists for first run or explicit recovery flow.

## Secrets Invariant

### Storage classes

| Class | Example | Allowed Storage |
|---|---|---|
| Root secret | `TOKEN_SIGNING_SECRET`, KMS key material | Env var / secret manager only |
| Operational secret | GitHub webhook secret, provider token cache | Encrypted DB field or env var |
| Derived metadata | verification timestamp, provider status | DB plaintext |

### Rules

1. Unencrypted secret persistence is forbidden.
2. Logs, PubSub payloads, artifacts, prompts, and UI all pass through redaction.
3. Secret rotation and revocation must be operationally documented.

## API Invariant (Ash + TypeScript RPC)

Canonical RPC endpoints:

- `POST /rpc/run`
- `POST /rpc/validate`

Generated client:

- `assets/js/ash_rpc.ts`

Coverage requirement:

- Setup actions
- Project import and workspace actions
- Orchestration and workflow run actions
- GitHub integration actions
- Support-agent configuration actions
- Forge orchestration actions required by product flows

## Deployment Invariant

- Cloud VM deployment is the production reference architecture.
- Local `mix phx.server` remains supported for development and fallback.
- Future Tauri packaging is tracked as an extension, not MVP.

## Governance

Any change that conflicts with a locked decision must:

1. Update this file first.
2. Update each impacted spec.
3. Update acceptance criteria in `02_requirements_and_scope.md`.
4. Add migration notes where behavior changes.
