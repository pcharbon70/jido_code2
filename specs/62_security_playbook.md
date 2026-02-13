# 62 — Security Playbook

## Overview

This playbook defines operational security practices for running JidoCode in production.

## Secret Lifecycle

### Create

1. provision root secret in environment/secret manager
2. create encrypted secret references for operational values
3. validate access without exposing values

### Rotate

1. create new secret version
2. update references atomically
3. verify dependent integrations
4. revoke prior version

### Revoke

1. disable compromised token/key
2. invalidate dependent sessions
3. force re-auth for affected integrations

### Audit

- track secret version, rotation timestamp, actor
- retain audit metadata for incident analysis

## Environment Hardening (Cloud VM)

1. enforce HTTPS
2. restrict host/origin configuration
3. secure webhook endpoint and signature verification
4. use least-privilege GitHub App permissions
5. isolate workspace execution environment

## Output/Data Protection

Redaction pipeline must cover:

1. logs
2. PubSub events
3. artifacts
4. prompt payloads
5. UI rendering

## Auth Operations

### Owner Bootstrap

- run once at onboarding
- disable open production registration after owner created

### Recovery

- documented owner recovery procedure
- token revocation and session invalidation support

### API Credential Governance

- API keys are scoped, revocable, and auditable
- unused API keys are rotated or revoked periodically

## Security Runbooks

### Suspected Secret Leak

1. classify leak vector
2. rotate impacted secrets
3. invalidate exposed sessions/tokens
4. review logs/artifacts for spread
5. document incident and resolution

### Webhook Spoof Attempt

1. verify signature mismatch pattern
2. rate-limit and block abusive source patterns
3. review idempotency and replay protections
4. escalate if repeated

### Token Compromise

1. revoke token immediately
2. rotate signing/issuer keys as needed
3. invalidate active sessions
4. force owner re-authentication

### PR Automation Abuse

1. disable shipping actions for affected workflow
2. inspect git policy logs and command audits
3. require manual approval escalation until resolved

## Operational Verification Checklist

- [ ] secret rotation test completed
- [ ] webhook signature validation test completed
- [ ] redaction validation test completed
- [ ] auth recovery drill completed
- [ ] git policy audit trail validation completed
