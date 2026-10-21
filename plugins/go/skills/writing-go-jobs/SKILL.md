---
name: writing-go-jobs
description: Write background jobs and timers in a Go backend with River on Postgres — job args with Kind, inserting in the same transaction as the state change, unique jobs, scheduled timers, queues and priorities, workers in the module's jobs package that run one use case and re-check state, retries with backoff and the discarded dead state, periodic jobs, rate-limited provider calls, tenant context, and tests with a stepping clock. Use when adding a timer, reminder, escalation, notification, export, recomputation, retention, or any work that must not run in the request.
---

# Writing Go jobs

Policy: the `backend-data` rule → Jobs; the `go-architecture` rule → Jobs. River's API changes between versions; check the installed godoc when a snippet does not compile.

## Args and enqueue

```go
// domain/jobs.go — plain data; ids only, never personal data or secrets.
type FooReminderArgs struct {
	TenantID string `json:"tenantId"`
	FooID    string `json:"fooId"`
}

func (FooReminderArgs) Kind() string { return "foos.reminder" }
```

- The use case enqueues through its transaction: `tx.Jobs().Enqueue(ctx, domain.FooReminderArgs{…}, domain.JobOptions{At: dueAt, Unique: true})`. `infra` implements it with `client.InsertTx(ctx, pgxTx, args, &river.InsertOpts{Queue: "timers", ScheduledAt: at, UniqueOpts: river.UniqueOpts{ByArgs: true}})`, so the job exists only if the transaction commits.
- One kind per purpose, named `<module>.<action>`. Args stay backward compatible (add optional fields only) because old jobs may still be in the queue during a deploy.
- The runtime River client sets `ReindexerIndexNames: []string{}`: the reindexer needs index ownership, which only the migrator has (`scaffolding-go-backend` → platform-templates.md).
- Queues by class: `timers` (time-critical, most workers, age alert), `notifications` (rate-limited channels), `exports` and `maintenance` (bulk, few workers). Set them in the River config of the `jobs` subcommand.

## Worker

```go
// jobs/reminder.go — a driver: one use case per job.
type FooReminderWorker struct {
	river.WorkerDefaults[domain.FooReminderArgs]
	remind *app.SendFooReminder
}

func (w *FooReminderWorker) Work(ctx context.Context, job *river.Job[domain.FooReminderArgs]) error {
	err := w.remind.Run(ctx, app.SendFooReminderInput{TenantID: job.Args.TenantID, FooID: domain.FooID(job.Args.FooID)})
	if errors.Is(err, domain.ErrFooNotFound) {
		return nil // gone since scheduling: nothing to do, do not retry
	}
	return err
}

func (w *FooReminderWorker) Timeout(*river.Job[domain.FooReminderArgs]) time.Duration { return 30 * time.Second }
```

- The use case runs in the job's tenant (`Transactor.InTenant(ctx, args.TenantID, …)`) and **re-checks current state** before acting: an item already decided, cancelled, or changed since scheduling is skipped. Idempotent: a second delivery changes nothing (a sent-marker row or a uniqueness key on the side effect).
- Return an error to retry (River backs off exponentially up to `MaxAttempts`, then marks the job discarded — the dead state, which alerts); return `river.JobCancel(err)` for a permanent failure that must not retry; return nil when there is nothing to do.
- External calls: a timeout per call, the provider's rate limit as a token bucket shared by workers of that queue, a circuit breaker with the fallback path; never inside a database transaction.
- One tenant cannot starve others: cap per-tenant concurrency in bulk queues (a uniqueness key per tenant, or a partitioned queue).
- Register workers in the `jobs` subcommand's wiring (`river.AddWorker(workers, &FooReminderWorker{…})`); the `api` process only inserts (an insert-only client).

## Periodic jobs

`river.NewPeriodicJob(river.PeriodicInterval(time.Hour), func() (river.JobArgs, *river.InsertOpts) { return domain.RetentionArgs{}, nil }, &river.PeriodicJobOpts{RunOnStart: false})` — leader election makes one instance schedule it. A periodic job that spans tenants either fans out one job per tenant or runs in the system role's package (a review zone).

## Tests

- Unit-test the use case behind the worker with the in-memory Transactor and a stepping clock: state changed since scheduling → no side effect; normal path → one side effect; second run → none.
- Integration on `testdb`: the use case that schedules inserts exactly one job in the same transaction (a rolled-back transaction leaves none; a duplicate is collapsed by uniqueness), using River's test helpers (`rivertest.RequireInserted…`) on the transaction or pool.
- Worker test: `rivertest.NewWorker(…).Work(…)` (or call `Work` with a constructed `river.Job`) with fakes for providers; assert retries on a transient provider error and no retry on a permanent one.
- Timers: advance the stepping clock across the due time and DST boundaries of the entity's zone; never sleep.
