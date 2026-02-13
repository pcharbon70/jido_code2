# 60 — Security & Auth

## Overview

JidoCode security is based on single-user AshAuthentication, encrypted secrets at rest, strict webhook verification, output redaction, and git safety guardrails.

## Security Objectives

1. Protect credentials and tokens.
2. Prevent unauthorized use of cloud-deployed instances.
3. Prevent accidental secret leakage in outputs and artifacts.
4. Ensure automated git/PR actions are policy constrained and auditable.

## Authentication Architecture (AshAuth)

### Single-User Policy

- One owner account per instance.
- Owner account is bootstrapped during onboarding.
- Production defaults disable open registration paths.

### Auth Modes

| Mode | Use Case |
|---|---|
| Session cookie | LiveView/browser interaction |
| Bearer token | API client automation |
| API key | service-style integrations |

### Auth Controls

- CSRF protection for browser POST/PUT/PATCH/DELETE flows.
- Token expiry and revocation required.
- Sign-out and token invalidation supported.

## Threat Model

### Protected Assets

- Provider credentials and tokens
- Repository access rights
- Workflow artifacts
- API authentication tokens

### Major Threats and Controls

| Threat | Control |
|---|---|
| Unauthenticated access | AshAuth gate + owner bootstrap policy |
| CSRF on authenticated browser flows | `protect_from_forgery` + session controls |
| Webhook spoofing | `X-Hub-Signature-256` verification + replay protection |
| Secret leakage in logs/output | mandatory redaction pipeline |
| Token compromise | rotate/revoke runbooks + short lifetimes |
| Unsafe git automation | mandatory policy checks in spec 52 |

## Secret Management

### Storage Policy

- Env vars are valid bootstrap/runtime sources.
- DB persistence is allowed only for encrypted secret fields.
- Unencrypted operational secret storage is forbidden.

### Encryption Policy

- Use `ash_cloak`/Cloak for encrypted fields.
- Track key version and rotation timestamps.
- Support secret rotation without downtime.

### Redaction Policy

Redaction applies before data is:

1. logged
2. published over PubSub
3. stored as artifact
4. sent to LLM prompt context
5. rendered in UI

## Webhook Security

- Signature verification is mandatory.
- Delivery ID idempotency check is mandatory.
- Raw payload and decision outcome are auditable.
- Failed verification responses are rate-limited and logged.

## API Security

- RPC and JSON API endpoints require actor context when action policy requires auth.
- Public actions are explicitly scoped and documented.
- Validation endpoint must not leak secret values.

## Deployment Security Baseline

Cloud VM (primary):

- HTTPS only
- strict host configuration
- secure secret injection
- network exposure limited to required endpoints

Local mode:

- default bind to localhost
- explicit warning if exposing externally

## Security Acceptance Criteria

1. No plaintext operational secrets in DB schema.
2. CSRF and auth boundary behavior documented and testable.
3. Webhook signature enforcement documented and testable.
4. Redaction policy coverage defined for all output channels.
5. Git automation references safety policy and cannot bypass it.
