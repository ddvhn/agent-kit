---
description: Backend operations — stages (pre-launch to scale), vendor independence, environments, a Load section in every PR, shed order, structured logs and metrics, deploys with migrations first and flags, rollback without hand-edited rows, incidents and post-mortems, backups that are restored
---

# Backend operations

Procedures, runbooks, observability setup, and drills: `running-backend-operations`; load planning and scaling thresholds: `planning-backend-load`. The project's stage, hosts, profile, windows, and targets: `CLAUDE.md`. Any deploy or production access is "ask first".

## Stages

Heavier practices start at the stage `CLAUDE.md` names; nothing here requires them earlier.

| Stage | Adds |
| --- | --- |
| 0 pre-launch | one app process, managed or single Postgres with daily backups, one external uptime check, error tracking |
| 1 first customers | staging, flags per tenant, deploy smoke, restore test, runbook |
| 2 paying load | hot standby, WAL archiving to another region, infrastructure as code, separate monitoring, SLO alerts, auto-rollback, drills |
| 3 scale | read replicas, pooler, partitions, multi-region synthetics, load and chaos runs |

## Infrastructure

- Self-hosted default: plain Postgres, storage through the S3 API, one Docker image running every process, 12-factor configuration, every provider behind a port, infrastructure as code (OpenTofu) from stage 2. No cloud functions, proprietary queues, or databases without an ADR (`backend-architecture` rule → Adopting a platform).
- Every PR that changes a query, endpoint, poll, job, or data flow has a "Load" section (traffic it handles on the profile, first bottleneck); others write "Load: no change". Trade-offs go to the user first.
- Under load, shed analytics first and critical writes never; heavy reads go to a replica once there is one; analytics never on the primary.
- Logs are structured JSON with request, tenant, and user ids and no personal data; metrics per contract operation; alerts on symptoms users feel.

## Environments and deploys

- `local` runs with fakes for every paid provider; `staging` runs the release build with real adapters on sandbox or test credentials; `staging` never holds production data; production runs the image staging tested.
- Migrations run before the code and are expand / contract; new behavior ships behind a flag; deploy outside peak hours with a smoke check after.

## Rollback and repair

- Roll back by previous image or flag; repair data forward with a tested migration or job. Never hand-edit production rows; append-only records are corrected by reversals.
- Production access is read-only by default, time-limited, and audited.

## Incidents

- Severities P1 (key function down, wrong money, data exposure) to P4; when unsure, P1. Mitigate first (rollback, flag, kill switch), then fix. Every P1 gets a blameless post-mortem with owned actions.

## Backups

- A backup that was never restored does not count: restores are tested on a temporary machine, never over production. RPO and RTO in `CLAUDE.md`.
