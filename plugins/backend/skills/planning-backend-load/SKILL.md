---
name: planning-backend-load
description: Plan and state the load cost of a backend change — derive requests, rows, jobs, and provider calls from the project's load profile with ×7 headroom, check hot queries with EXPLAIN on realistic data, N+1, locks and long transactions, fan-out, queue backlog, payload and pool use, decide caching and replica reads, and write the PR's Load section; also the scaling thresholds and the shed order under peaks. Use when a change adds or alters a query, endpoint, poll, job, fan-out, export, or provider call, when writing a Load section, or when asked whether the backend will hold a load.
---

# Planning backend load

Policy: the `backend-operations` rule → Infrastructure. The project's load profile, stage goal, targets, and thresholds: `CLAUDE.md` → Project facts. If the project has no load profile, write one first (below) and ask the user to confirm the numbers.

## Load profile (once per project, updated per stage)

| | Stage goal | ×7 headroom |
| --- | --- | --- |
| Tenants / active users | | |
| Writes per day; peak share in the peak window (for example 30% in 30 minutes) | | |
| API requests per second at peak (reads, polls, writes) | | |
| Media per day and stored over retention | | |
| Notifications per peak minute | | |
| Append-only rows per year | | |
| Concurrent calls to each rate-limited provider | | |

Peaks come from the product's rhythm (opening hours, hourly reminders, end of month), clients returning after an outage, onboarding a large tenant, and bots. Name them.

## Default targets (`CLAUDE.md` wins)

API p95 ≤ 500 ms for key operations, errors < 0.1% at the profile ×7, time-critical jobs start within 60 s of schedule, transactions short (alert on the oldest open one).

## Per change

1. **Count**: requests per screen open and per poll (one delta instead of many reads), queries per request (no query in a loop), rows read and written, jobs enqueued, provider calls, payload size. Multiply by the profile's peak and the headroom.
2. **Queries**: write each new or changed query, seed realistic volume (the largest tenant × headroom, not ten rows), and run `EXPLAIN (ANALYZE, BUFFERS)`. Indexes lead with the tenant id; no sequential scan of a large table on a hot path; period queries hit one partition. Name the query in code so it shows in `pg_stat_statements`.
3. **Transactions and locks**: keep them short; no network or provider call inside; row locks only on the aggregate that needs them, in a consistent order; no advisory lock held across requests. Long transactions also hold vacuum and change-log horizons.
4. **Fan-out**: one event → how many rows, jobs, pushes, messages? Batch (push in batches, chunked inserts), spread over time, and respect provider rate limits with a token bucket in the job queue.
5. **Queues**: job duration × peak rate vs workers; time-critical queues separate and prioritized; uniqueness keys to collapse duplicates; one tenant's backlog cannot starve others.
6. **Reads**: can it come from the replica (dashboards, exports, reports)? From an in-process cache with a short TTL and event invalidation? Never cache across tenants without the tenant in the key; never cache signed URLs.
7. **Payload**: page size capped; no unbounded nested arrays; media goes client ↔ storage by signed URL, never through the API.
8. **Pool**: concurrent requests × queries in flight vs the pool size and the database `max_connections`; when app servers grow, a transaction-mode pooler (the tenant context with `set_config(…, true)` works there). Prepared statements do not survive a transaction-mode pooler unless it tracks them: use PgBouncer ≥ 1.21 with `max_prepared_statements` set, or switch the driver off its statement cache (pgx: `DefaultQueryExecMode` = `QueryExecModeExec` or `QueryExecModeDescribeExec`).
9. **First bottleneck**: say which resource breaks first at what load, and what the mitigation is (index, batch, cache, replica, shed, scale).

## Load section template (PR)

```markdown
## Load
- Pattern: <what runs, how often> — at stage peak ×7: <N req/s, M rows/s, K jobs/min, P provider calls/min>.
- Queries: <name> uses <index>; EXPLAIN on <volume>: <time>, <rows>.
- First bottleneck: <resource> at <load>; mitigation: <…>.
- Trade-offs for the user: <none | what and why>.
```

A change with no such effect writes `Load: no change`.

## Shed order under peaks

1. Refuse product analytics and telemetry batches (`503` + `Retry-After`; clients keep their buffer).
2. Delay exports and recomputations (queue them, one per tenant per minute).
3. Serve dashboards from the replica and cache.
4. Raise the poll interval header.
5. Never shed critical writes (submissions, decisions, payments) or time-critical jobs.

Instrument rejections by reason (`rate_limit`, `shed`, `timeout`) so the shedding is visible.

## Scaling thresholds (defaults, `CLAUDE.md` wins)

Act when a threshold holds at the weekly peak for two weeks or a forecast reaches it within 30 days:

| Signal | Threshold | Action |
| --- | --- | --- |
| App CPU at peak, or key p95 over target with CPU the cause | > 60% | Add an app server |
| Database CPU at peak | > 60% | Larger machine (vertical) |
| Cache hit ratio / working set | < 99% / > 70% of RAM | More memory |
| Connections | > 60% of the limit | Transaction-mode pooler |
| Heavy reads | > 30% of database time | Read from the replica |
| Large table | > 50 M rows or slow period queries | Time partitions |
| Time-critical job start delay | p99 > 10 s at peak | More workers, then a separate jobs machine |
| Disk | forecast < 30 days | Bigger disk, check bloat and WAL |

## Verifying

Load scripts in the repository against staging, whose real adapters point at provider sandboxes or a stub provider server (never in-process fakes): the peak scenario at headroom with p95, error rate, and queue lag recorded in the PR (`testing-backends` → Load and chaos).
