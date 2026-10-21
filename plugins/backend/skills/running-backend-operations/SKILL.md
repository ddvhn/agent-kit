---
name: running-backend-operations
description: Prepare and run backend operations — environment setup, the deploy checklist (migrations first, flags, windows, error budget, smoke, auto-rollback), rollback and data repair, incident response with severities and kill switches, the blameless post-mortem template, backups and restore drills, database failover, observability setup (logs, metrics, SLOs, burn-rate alerts, synthetics, dashboards), and the runbook outline. Use when writing or changing a runbook, deploy or rollback steps, alerts or dashboards, during or after an incident, or when planning backup, restore, and failover drills.
---

# Running backend operations

Policy: the `backend-operations` rule (stages decide which parts below apply yet). The project's runbook path, hosts, deploy tool, windows, severities, and on-call: `CLAUDE.md` → Project facts. Any deploy or production access is "ask first": prepare the steps and the commands, and let the user run or approve them.

## Infrastructure defaults (self-hosted)

- Object storage through the plain S3 API (endpoint, bucket, keys from config; a local S3-compatible server in development); private buckets; uploads and downloads by signed URL straight between client and storage.
- Plain Postgres from your own image with open-source extensions (`pg_stat_statements`, `pgvector`); no proprietary engines.
- One Docker image (static binary or slim runtime, non-root) runs every process by subcommand; production runs the digest staging tested.
- Configuration from the environment only; the process fails at start on missing config. Secrets via SOPS or the host's secret store.
- From stage 2: infrastructure as code (OpenTofu) for machines, network, firewall, load balancer, DNS, buckets; a self-hosted, open-source monitoring stack on a machine apart from production.
- No orchestrator until there are more than a handful of servers; scale by thresholds (`planning-backend-load` → Scaling thresholds).

## Environments

- `local`: one command starts the database, S3-compatible storage, a mail catcher, and fakes for every paid provider.
- `staging` (stage 1+): from the main branch, synthetic data only, separate accounts, keys, buckets, and bots; test-only controls (shifting a tenant's clock) exist only there and are audited.
- `production`: from the release branch, manual approval.

## Runbook outline

Keep one runbook in the repository (for example `infra/RUNBOOK.md`); each section has exact commands and a time target.

1. Access (who, how, break-glass), environments, where secrets live.
2. Deploy, rollback, feature flags.
3. Incident: severity, first 15 minutes, roles (lead, communicator), status page, notice banner, incident mode.
4. Kill switches, one line each with its command and audit trail.
5. Database: failover, restore to a point in time, replica rebuild, long transaction and lock triage, bloat.
6. Queue: dead jobs, backlog, pausing a queue, replaying.
7. Providers: outage of each, fallback switch, rate-limit exhaustion.
8. Scaling: add an app server, resize the database, add a pooler (`planning-backend-load` → Scaling thresholds).
9. Secrets: rotation of each, leak response.
10. Drills calendar and their last results.

## Deploy checklist

- [ ] The image passed staging (same digest); the smoke scenario green there.
- [ ] Migrations are expand / contract and ran on a copy of realistic data; `lock_timeout` set.
- [ ] New behavior behind a flag, off; the pilot tenant named.
- [ ] Outside peak hours and not before a weekend, no open P1 / P2; from stage 2, error budget less than half spent (or this is a fix).
- [ ] Rollback path written: previous image digest, flag name.
- Run: migrate → deploy → smoke → watch 15 minutes (5xx, p95, queue lag, dead jobs) → turn the flag on for the pilot tenant.
- From stage 2, auto-rollback: 5xx > 1% for 5 minutes, or the synthetic scenario failing from 2+ regions.
- Mobile clients cannot be rolled back: stop the staged rollout, turn the feature off, ship a fix, raise the minimum supported version only when the fix is live.

## Rollback and data repair

- Code: redeploy the previous image digest. Feature: flag off. Do both before debugging.
- Data: stop the writing feature, write a forward fix (migration or job) with a test on a copy of the broken shape, review it, run it; append-only records are corrected by reversals. Never hand-edit rows.

## Incident response

1. Declare: severity (P1 when unsure), an incident channel, the lead.
2. Protect people: if the product has timers or deadlines that would penalize users, freeze them for the affected tenants; a notice served by the API and a status page entry within 15 minutes when the project has them.
3. Mitigate: rollback, flag off, kill switch, failover. Fix later.
4. Communicate every 30 minutes until resolved; record the timeline as you go.
5. Close: confirm metrics normal, record downtime per tenant with reasons for any exclusion, open the post-mortem.

### Post-mortem template (blameless, within 5 business days)

```markdown
# <date> <title> (P<n>)
- Impact: who, what, how long, data or money affected
- Timeline (UTC): detection, declaration, mitigation, resolution
- Root cause and contributing factors (systems, not people)
- Detection: what alerted, what should have
- What went well / what hurt
- Actions: <action> — owner — date — tracking link
```

## Kill switches

Each audited, each one command in the runbook: end sessions (user, tenant, all), stop uploads, stop sending data to a provider or switch to its fallback, turn a paid channel off, turn an endpoint or feature off, put a tenant in read-only, block an IP, identifier, or device.

## Backups, restore, failover

- Stage 0: daily managed or `pg_dump` backups kept off the machine; a restore tested once and after every major change.
- Stage 2: nightly full, incrementals, WAL archiving every minute to another region, write-once and encrypted with a key kept apart; RPO ≤ 1 minute, RTO ≤ 2 hours; a hot standby.

- Verify continuously: the restore job (temporary machine, latest backup + WAL, compare row counts and sums of append-only records) reports daily or weekly; a failure pages.
- Point-in-time restore: to a new machine, never over production; extract the needed rows; repair forward.
- Failover (stage 2, target 15 minutes): stop job workers → promote the replica → fence the old primary (firewall) → switch the connection secret → redeploy → verify money sums and the smoke scenario → start workers → rebuild a replica the same day.
- Drills quarterly on staging with a stopwatch; record the time; over target → fix the runbook.

## Observability setup

- **Logs**: JSON to stdout, one summary line per request and job (request id, operation, status, duration, tenant and user ids, app version; job kind, id, attempt), levels `error` (needs a human) / `warn` / `info` (one line per unit of work) / `debug` (off in production), a masking layer for personal data, shipped by a collector to a self-hosted store with 14–30 days retention; polls without changes sampled.
- **Metrics**: HTTP middleware labels by contract operation id; database pool and `pg_stat_statements` exporter; queue depth, oldest job age, start delay, dead jobs; runtime and host metrics.
- Stage 0–1: error tracking, one uptime check, the request log; alerts on 5xx rate and the check. Everything below from stage 2.
- **SLOs**: availability (non-5xx and under 10 s) and latency (under the p95 target) of key operations, time-critical job start delay. Burn-rate alerts: 1 h and 5 min windows at 14.4× (page), 6 h and 30 min at 6× (page), 3 d and 6 h at 1× (ticket), only above a minimum request count.
- **Leading indicators**: disk days-to-full, pool wait p95, connections share, oldest transaction age, replica lag, dead tuples, queue age, provider error rate and quota.
- **Synthetics** (stage 3; stage 2 one region): the main user path every minute from 3 regions on a synthetic tenant; page when 2+ fail. The status page and the monitoring stack run apart from production.
- **Dashboards**: overview (SLOs, budget left, traffic vs last week), API per operation, database, queues, providers, per-tenant top 10 by requests and rejections.
- Test the monitoring itself: a dead-man alert that fires when the alert pipeline is silent.
