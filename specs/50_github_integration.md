# 50 — GitHub Integration

## Overview

GitHub integration powers repository import, webhook-triggered Issue Bot workflows, and PR creation in JidoCode.

## Auth Paths

### Primary: GitHub App

- user-managed app credentials
- installation-scoped access
- webhook signature verification support

### Fallback: Personal Access Token

- supported for simpler setup
- reduced security granularity
- webhook automation may be limited by configuration

## Secret Handling

- root secret sources may come from env vars
- operational GitHub secrets/tokens may be persisted only in encrypted DB fields
- no plaintext webhook secret persistence

## Repo Import Flow

1. verify integration credentials
2. list accessible repos
3. create project records
4. clone/sync workspaces
5. emit import status events

## Webhook Pipeline (MVP)

Endpoint: `POST /api/github/webhooks`

Processing sequence:

1. verify `X-Hub-Signature-256`
2. enforce idempotency by delivery ID
3. persist delivery record
4. map event to trigger rules
5. dispatch workflow/support-agent actions

## MVP Event Coverage

| Event | Behavior |
|---|---|
| `issues.opened` | trigger Issue Bot workflow |
| `issues.edited` | trigger re-triage policy |
| `issue_comment.created` | optional follow-up context trigger |
| `installation.*` | keep repo availability and install metadata in sync |

## Issue Bot Trigger Contract

- project must have Issue Bot enabled
- webhook event must match configured list
- approval policy determines auto-post vs human gate

## API Client Requirements

- use `Req`
- explicit timeout and retry behavior
- map GitHub errors to typed internal failures

## Rate Limits and Token Refresh

- monitor remaining quota
- refresh app installation tokens ahead of expiry
- cache token metadata safely; secret value handling follows encrypted storage policy

## Data Mapping

| GitHub Concept | JidoCode Resource |
|---|---|
| Repository | `Project` / `GitHub.Repo` |
| Installation | integration metadata + encrypted secret refs |
| Webhook delivery | `WebhookDelivery` |
| Issue analysis | `IssueAnalysis` |
| Pull request | `PullRequest` |
