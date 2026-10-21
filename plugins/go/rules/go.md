---
description: Go language standards — gofmt and linters, errors as values (wrap with %w, errors.Is / As, typed errors, no panics), context first, small consumer-side interfaces, explicit constructors, goroutine lifetimes, slog with ids only, time from a clock, no hand-edited generated code
paths:
  - "**/*.go"
  - "**/go.mod"
---

# Go

The Go version in `go.mod`; use what it offers (`slices`, `maps`, `log/slog`, `net/http` patterns, `testing.F`).

- `gofmt`, `go vet`, and `golangci-lint` clean; `//nolint:<linter> // reason` only with a reason, mentioned in the PR.
- Errors are values: return them, never panic for expected failures; wrap once with context (`fmt.Errorf("load foo %s: %w", id, err)`); compare with `errors.Is` / `errors.As`, never by text; driver errors never leave the repository. Handle each error once (return or log, not both).
- `ctx context.Context` is the first parameter of anything doing I/O or blocking; never stored in a struct.
- Interfaces are small and declared by the consumer; accept interfaces, return structs; assert implementations at compile time (`var _ domain.FooRepository = (*FooRepository)(nil)`).
- Constructors take every dependency explicitly; no package-level mutable state, no `init()` with side effects; config read once in `main`.
- Value types (ids, money, statuses) validate in their constructor and are never mutated.
- Names: short lowercase packages, no `util` / `common`, no stutter, doc comments on exported identifiers, `ID` / `URL` / `HTTP` in one case, files named after their type or action.
- Goroutines have an owner and an end (context, `errgroup`); shared state behind a mutex or channel; `-race` clean.
- Time from the injected clock, never `time.Now()` outside it and `main`; `time/tzdata` imported in `main`.
- `log/slog`, structured, ids only; never `fmt.Println` or `log` in server code.
- HTTP clients with a timeout and `NewRequestWithContext`; bodies closed. Money in `int64` minor units.
- Generics only for real reuse; no reflection in business code; no `unsafe` or cgo without a decision.
- Never hand-edit generated files (`*.gen.go`, sqlc output): change the input, `make generate`.
