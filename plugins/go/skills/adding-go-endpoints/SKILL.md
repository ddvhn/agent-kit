---
name: adding-go-endpoints
description: Add or change a REST operation in a Go backend contract-first — edit api/openapi.yaml, regenerate the oapi-codegen strict server and the 501 fallback, write the failing API tests (contract-validated responses, every declared error code, RBAC and cross-tenant cases, idempotency), implement the strict handler that resolves the actor and calls one use case, map domain ↔ apigen types, and promote the operation from draft to stable. Use when adding an endpoint, a field, a query parameter, or an error code to a Go backend, or implementing a draft operation.
---

# Adding a Go endpoint

Contract design and compatibility: `designing-api-contracts` (do that first). Policy: the `backend-api` rule and the `go-architecture` rule → HTTP. The use case behind it: `writing-go-use-cases`. Neighbor handlers and API tests: `CLAUDE.md` → Project facts.

## Workflow

1. **Contract**: add or change the operation in `api/openapi.yaml` with milestone and `draft`; list every error response; add new codes to the conventions page.
2. `make generate`. The new operation now answers `501` through the fallback; `go build ./...` passes.
3. **Tests first** in `internal/server/foos_test.go` (below); run them and see them fail on `501` or the missing behavior.
4. **Use case** in the module's `app` (`writing-go-use-cases`), with its own unit tests.
5. **Handler** in the module's `api` (template below); remove nothing from the fallback (it is generated; the module's method wins by embedding depth).
6. Flip `x-…-status` to `stable`, `make generate`, `make check`.
7. PR: requirement ids, the contract diff, the red and green runs, Load (`planning-backend-load`) and Compliance sections, and the client changes to make.

## Handler template

```go
// UpdateFoo handles PATCH /v1/foos/{fooId}.
func (h *Handler) UpdateFoo(ctx context.Context, req apigen.UpdateFooRequestObject) (apigen.UpdateFooResponseObject, error) {
	actor, err := h.actors.Resolve(ctx, req.Params.MembershipId) // principal from ctx; foreign or inactive → ErrNotFound
	if err != nil {
		return nil, err
	}
	id, err := domain.ParseFooID(req.FooId.String()) // format: uuid → openapi_types.UUID
	if err != nil {
		return nil, apperr.ErrNotFound
	}
	out, err := h.updateFoo.Run(ctx, app.UpdateFooInput{Actor: actor, ID: id, Name: req.Body.Name})
	if err != nil {
		return nil, err // mapped once by httpx.Error
	}
	return apigen.UpdateFoo200JSONResponse(fooToAPI(out.Foo)), nil
}
```

- The handler parses ids and maps types; it never decides anything. One use case per handler.
- Every failure is `return nil, err` with a typed error; the strict server's response error handler writes the contract's error shape. Never write an error body by hand.
- `h.actors` is a small interface the module's `api` declares, implemented by the tenants module's root package (passed in by `wire.go`).
- Mapping functions live in `api/mapping.go`: `fooToAPI(domain.Foo) apigen.Foo`, instants as `time.Time` in UTC (the generator formats RFC 3339), money as `apigen.Money{AmountMinor, Currency}`, enums through an exhaustive `switch` (an unmapped value is a bug, returned as an error).
- Lists: parse `cursor` into the keyset (`after`), clamp `limit` to the contract maximum, fetch `limit+1`, return `nextCursor` only when there is a next page.

## API test template

```go
func TestUpdateFoo(t *testing.T) {
	e := newEnv(t)
	a := e.newTenant("Owner A")
	b := e.newTenant("Owner B")
	foo := a.createFoo("First")

	t.Run("refusals", func(t *testing.T) {
		for _, tc := range []struct {
			name   string
			r      req
			status int
			code   string
		}{
			{"no token", req{body: map[string]any{"name": "x"}}, 401, "auth.unauthorized"},
			{"no membership header", req{token: a.owner.token, body: map[string]any{"name": "x"}}, 400, "validation.invalid"},
			{"foreign tenant", b.owner.as(b.membership, map[string]any{"name": "x"}), 404, "notFound"},
			{"role without the permission", a.member.as(a.memberMembership, map[string]any{"name": "x"}), 404, "notFound"},
			{"name too long", a.owner.as(a.membership, map[string]any{"name": strings.Repeat("я", 201)}), 400, "validation.invalid"},
			{"unknown field", a.owner.as(a.membership, map[string]any{"name": "x", "status": "published"}), 400, "validation.invalid"},
		} {
			t.Run(tc.name, func(t *testing.T) {
				r := e.call("PATCH", "/v1/foos/"+foo.Id, tc.r)
				if r.status != tc.status || r.code() != tc.code {
					t.Fatalf("got %d %s, want %d %s: %s", r.status, r.code(), tc.status, tc.code, r.body)
				}
			})
		}
	})

	t.Run("owner renames", func(t *testing.T) {
		var got apigen.Foo
		e.must(200, "PATCH", "/v1/foos/"+foo.Id, a.owner.as(a.membership, map[string]any{"name": "Zoë Ñ 🙂"}), &got)
		if got.Name != "Zoë Ñ 🙂" {
			t.Fatalf("name %q", got.Name)
		}
	})
}
```

- Adversarial cases first, happy path last; one case per declared error code; the state-based codes (`409`, `410`) provoked through real prior calls.
- Retryable writes: the same `Idempotency-Key` twice in a row, twice concurrently (goroutines + `sync.WaitGroup`), and with a different body (`422`), plus the cases in the project's idempotency ADR; assert one row through the admin pool.
- State is built through the API helpers (`newTenant`, `createFoo`), not by inserting rows, so tests exercise the real paths.
- `checkContract` runs inside `call`; an extra field or an undocumented status fails without extra assertions.
