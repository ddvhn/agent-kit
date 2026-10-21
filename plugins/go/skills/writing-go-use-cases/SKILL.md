---
name: writing-go-use-cases
description: Write or change a use case in a Go backend module — one file and one struct named verb-first with Run(ctx, in) (out, error), its input and output types, the permission check on the actor and resource, domain functions for the rules, one transaction through the Transactor with the change hint, audit row, and jobs in it, typed errors, and table-driven unit tests with an in-memory Transactor plus integration coverage. Use when adding business behavior, a state transition, or a write path, or when refactoring a module-wide Service into use cases.
---

# Writing Go use cases

Policy: the `backend-architecture` rule → Use cases; the `go-architecture` rule → Use cases. Transactions and repositories: the `go-data` rule. Neighbor use cases: `CLAUDE.md` → Project facts.

## Shape

```go
// Package app holds the foos use cases.
package app

// PublishFoo publishes a draft foo; only actors who may edit it, only from draft.
type PublishFoo struct {
	tx    domain.Transactor
	clock clock.Clock
}

type PublishFooInput struct {
	Actor authz.Actor
	ID    domain.FooID
}

type PublishFooOutput struct{ Foo domain.Foo }

func NewPublishFoo(tx domain.Transactor, clk clock.Clock) *PublishFoo {
	return &PublishFoo{tx: tx, clock: clk}
}

func (uc *PublishFoo) Run(ctx context.Context, in PublishFooInput) (PublishFooOutput, error) {
	var out PublishFooOutput
	err := uc.tx.InTenant(ctx, in.Actor.TenantID, func(ctx context.Context, tx domain.Tx) error {
		foo, err := tx.Foos().GetForUpdate(ctx, in.ID)
		if err != nil {
			return err // ErrFooNotFound
		}
		if !domain.CanEditFoo(in.Actor, foo) {
			return domain.ErrFooNotFound // forbidden is the same error as missing: same code, same message
		}
		published, err := foo.Publish(uc.clock.Now()) // the rule lives on the aggregate
		if err != nil {
			return err // ErrFooAlreadyPublished
		}
		if err := tx.Foos().Update(ctx, published); err != nil {
			return err
		}
		if err := tx.Audit().Write(ctx, "foo.published", string(foo.ID), foo, published); err != nil {
			return err
		}
		if err := tx.Changes().Record(ctx, "foo", string(foo.ID), domain.OpUpsert); err != nil {
			return err
		}
		out.Foo = published
		return nil
	})
	return out, err
}
```

## Rules of thumb

- One action per type. Two jobs → two use cases; a flag in the input that switches behavior is a smell.
- The struct holds ports only (Transactor, clock, provider ports, ids generator if injected); never another use case, never a `*pgxpool.Pool` directly.
- Order inside the transaction: load (with `ForUpdate` when the action races), authorize on the loaded resource, decide with a pure domain function, persist, audit, change hint, enqueue jobs. All reads before writes where possible.
- Decisions are pure domain functions or methods taking `now` (`foo.Publish(now)`); they get the table-driven tests. The use case only orchestrates.
- No provider calls inside the transaction: enqueue a job (`tx.Jobs().Enqueue`) or call after commit, idempotently.
- Errors: return typed `apperr` errors from the domain or repository unchanged; wrap only unexpected ones with context (`fmt.Errorf("publish foo %s: %w", id, err)`), which surface as `500`.
- A read-only use case still runs in a transaction with the tenant scope (RLS needs it); use the snapshot variant when several reads must agree.
- Shared logic between two use cases moves down into the domain or one repository method, never into a third use case (core `same-level-dependencies`).

## Tests

Unit tests in `app/publish_foo_test.go` with the in-memory Transactor from `app/fakes_test.go`:

```go
func TestPublishFoo(t *testing.T) {
	now := time.Date(2026, 1, 13, 7, 0, 0, 0, time.UTC)
	tests := []struct {
		name    string
		actor   authz.Actor
		seed    domain.Foo
		wantErr error
	}{
		{"missing foo", owner, domain.Foo{}, domain.ErrFooNotFound},
		{"other tenant", ownerOfB, draftFoo, domain.ErrFooNotFound},
		{"member without edit", member, draftFoo, domain.ErrFooNotFound},
		{"already published", owner, publishedFoo, domain.ErrFooAlreadyPublished},
		{"owner publishes draft", owner, draftFoo, nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tx := newFakeTransactor(tt.seed)
			_, err := app.NewPublishFoo(tx, clock.NewStepping(now)).Run(context.Background(), app.PublishFooInput{Actor: tt.actor, ID: draftFoo.ID})
			if !errors.Is(err, tt.wantErr) {
				t.Fatalf("err %v, want %v", err, tt.wantErr)
			}
			if tt.wantErr == nil && (len(tx.audit) != 1 || len(tx.changes) != 1) {
				t.Fatalf("audit %d, changes %d; want one each", len(tx.audit), len(tx.changes))
			}
			if tt.wantErr != nil && (len(tx.audit) != 0 || len(tx.changes) != 0) {
				t.Fatal("a refused action wrote audit or changes")
			}
		})
	}
}
```

- The fake Transactor keeps rows in maps keyed by tenant, rolls back its staged writes when `fn` returns an error, and records audit, changes, and jobs for assertions.
- Races (two concurrent publishes, a publish racing a timer) are tested on `testdb` with real transactions in `infra` or API tests: one wins, the other gets the typed conflict, never a 500.
- The API test of the operation covers the transport cases (`adding-go-endpoints`); do not repeat the domain edge cases there.
