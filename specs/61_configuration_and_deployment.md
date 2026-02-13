# 61 — Configuration & Deployment

## Overview

JidoCode is deployed **cloud VM first** (Fly Machine style). Local mode remains supported for development and fallback self-hosting. Future local desktop packaging (Tauri-style) is a planned extension.

## Deployment Modes

### Cloud VM (Primary Production Mode)

- Public HTTPS endpoint
- Postgres-backed persistence
- Sprites/cloud workspace as default runtime
- GitHub webhooks delivered directly

### Local Development/Fallback Mode

- `mix phx.server`
- local or remote Postgres
- localhost binding by default
- webhook tunneling required for external events

### Future Mode (Planned)

- Tauri-style packaged local desktop deployment
- embedded runtime with managed local config/secrets UX

## Required Environment Variables

| Variable | Purpose |
|---|---|
| `SECRET_KEY_BASE` | Phoenix signing/encryption key |
| `DATABASE_URL` | Postgres connection |
| `PHX_HOST` | host for URL generation |
| `TOKEN_SIGNING_SECRET` | auth token signing secret |

## Provider and Integration Variables

| Variable | Purpose |
|---|---|
| `ANTHROPIC_API_KEY` | LLM provider |
| `OPENAI_API_KEY` | optional provider |
| `GOOGLE_AI_API_KEY` | optional provider |
| `GITHUB_APP_ID` | app identifier |
| `GITHUB_APP_PRIVATE_KEY` | app private key source |
| `GITHUB_WEBHOOK_SECRET` | webhook verification source |
| `GITHUB_PAT` | fallback GitHub auth |
| `SPRITES_API_TOKEN` | cloud workspace auth |

## Secret Configuration Model

1. Root secrets provided by env/secret manager.
2. Operational secrets may be persisted only in encrypted DB fields.
3. Secret references and metadata remain queryable without exposing values.

## Runtime Configuration Principles

- No hardcoded credentials.
- Runtime validation for missing required values.
- Cloud defaults favor secure public deployment.
- Local defaults favor developer safety (`localhost`, explicit opt-in exposure).

## Fly-Style Deployment Baseline

1. Provision app and Postgres.
2. Set required secrets.
3. Run migrations.
4. Enable HTTPS and health checks.
5. Configure GitHub webhook endpoint.

## Health and Readiness

- Health endpoint remains available for platform probes.
- Readiness should include DB connectivity and key services required for workflow start.

## RPC and API Deployment Requirements

- `/rpc/run` and `/rpc/validate` are available in deployed environment.
- Generated TypeScript client must match deployed action inventory version.
- API auth modes (session, bearer, api_key) are documented and validated.

## Local Development Quick Start

```bash
cp .env.example .env
source .env
mix setup
mix phx.server
```

## Operational Checklist

- [ ] Owner account bootstrap path verified
- [ ] Secrets loaded from secure source
- [ ] Encrypted secret persistence configured
- [ ] Webhook signature verification configured
- [ ] RPC endpoints operational
- [ ] Git safety policy referenced by workflow shipping actions

## Forward Plan: Tauri Packaging

When desktop packaging is introduced, specs must define:

1. local secret storage model
2. update channel and signature verification
3. migration path from local dev deployment
