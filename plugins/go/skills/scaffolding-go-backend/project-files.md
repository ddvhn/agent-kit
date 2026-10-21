# Project files

Pin every tool and module to its current release at scaffold time; the versions below are examples.

## go.mod (direct dependencies)

```
module example.com/app

go 1.25

require (
	github.com/caarlos0/env/v11
	github.com/getkin/kin-openapi
	github.com/golang-jwt/jwt/v5
	github.com/google/uuid
	github.com/jackc/pgx/v5
	github.com/oapi-codegen/nethttp-middleware
	github.com/oapi-codegen/runtime
	github.com/pressly/goose/v3
	github.com/riverqueue/river                 // with the first job
	github.com/riverqueue/river/riverdriver/riverpgxv5
	pgregory.net/rapid                          // tests
)
```

## Makefile

```make
# `make help` lists targets. Integration tests need Postgres:
#   docker compose up -d postgres && make db-bootstrap
#   export APP_TEST_DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres?sslmode=disable

GORUN         := GOTOOLCHAIN=$(shell go env GOVERSION) go run
SQLC          := $(GORUN) github.com/sqlc-dev/sqlc/cmd/sqlc@v1.29.0
OAPI_CODEGEN  := $(GORUN) github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@v2.5.0
GOLANGCI_LINT := $(GORUN) github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.1.6
GOVULNCHECK   := $(GORUN) golang.org/x/vuln/cmd/govulncheck@v1.1.4
GENERATED     := internal/platform/apigen internal/server/unimplemented.gen.go internal/*/infra/db

.PHONY: help generate check-generated fmt lint vuln test-unit test cover check check-release hooks build run migrate db-up db-bootstrap smoke-live

help: ## Show targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

generate: ## API types and strict server, the 501 fallback, sqlc queries
	cd internal/platform/apigen && $(OAPI_CODEGEN) -config oapi-codegen.yaml ../../../api/openapi.yaml
	go run ./tools/genunimpl -in internal/platform/apigen/apigen.gen.go -out internal/server/unimplemented.gen.go
	$(SQLC) generate

check-generated: generate ## Fail when generated code is stale
	git diff --exit-code -- $(GENERATED)

fmt: ## Format
	gofmt -w cmd internal tools

lint: ## go vet and golangci-lint (boundaries, gosec)
	go vet ./...
	go vet -tags release ./...   # the release-only files compile and vet too
	$(GOLANGCI_LINT) run ./...

vuln: ## Known vulnerabilities in dependencies
	$(GOVULNCHECK) ./...

test-unit: ## Unit tests (no Postgres)
	go test -short ./...

test: ## Everything against Postgres
	go test -race -count=1 ./...

cover: ## Coverage of handwritten code, gated
	go test -race -count=1 -coverpkg=./... -coverprofile=cover.out ./...
	./tools/covergate.sh cover.out coverage-exclusions.txt 100

check: check-generated lint check-release test cover ## What every PR runs

hooks: ## Install git hooks
	git config core.hooksPath .githooks

build: ## Build bin/app
	CGO_ENABLED=0 go build -tags release -trimpath -o bin/app ./cmd/app

check-release: ## The release build contains no fakes (any package named fakes or under a fakes/ directory); a failing go list fails the target
	@out=$$(go list -deps -f '{{.ImportPath}} {{.Name}}' -tags release ./cmd/app) || exit 1; \
	printf '%s\n' "$$out" | grep -E '(/fakes(/| )|^[^ ]+ fakes$$)'; rc=$$?; \
	[ $$rc -eq 1 ] || { echo "fakes in the release build, or grep failed ($$rc)"; exit 1; }

run: ## Run the API locally
	go run ./cmd/app api

migrate: ## Apply migrations
	go run ./cmd/app migrate

db-up: ## Start local Postgres
	docker compose up -d postgres

db-bootstrap: ## Roles and database in local Postgres (dev passwords)
	docker compose exec -T postgres psql -U postgres -v ON_ERROR_STOP=1 -v migrator_password=dev -v app_password=dev -v system_password=dev -f - < deploy/postgres/bootstrap.sql

smoke-live: ## Real providers, by hand only, with a call budget
	APP_LIVE=1 go test -tags live -count=1 ./internal/smoke/...
```

`tools/covergate.sh`: filter `cover.out` with `grep -v -E -f coverage-exclusions.txt`, run `go tool cover -func`, compare the `total:` percentage with the threshold, print uncovered functions, exit 1 below it.

`coverage-exclusions.txt` (one regex per line, a comment with the reason each):

```
# generated
/internal/platform/apigen/
/internal/[a-z]+/infra/db/
\.gen\.go:
# flag parsing and process start
/cmd/app/
# real paid-provider adapters (their mapping is tested against httptest stubs)
/internal/[a-z]+/infra/live_
```

## .golangci.yml

```yaml
version: "2"
linters:
  enable: [depguard, gosec, errorlint, bodyclose, noctx, misspell]
  settings:
    depguard:
      rules:
        # A module is used by others only through its root package; internal/server wires internals.
        foos-internals:
          files: ["$all", "!**/internal/foos/**", "!**/internal/server/**"]
          deny:
            - { pkg: example.com/app/internal/foos/, desc: use the foos root package }
        domain-pure:
          files: ["**/internal/*/domain/**"]
          deny:
            - { pkg: example.com/app/internal/foos/app, desc: domain is the lowest layer }
            - { pkg: example.com/app/internal/foos/infra, desc: domain is the lowest layer }
            - { pkg: example.com/app/internal/foos/api, desc: domain is the lowest layer }
            - { pkg: example.com/app/internal/foos/jobs, desc: domain is the lowest layer }
            - { pkg: example.com/app/internal/foos$, desc: domain does not call modules; the use case does }
            - { pkg: example.com/app/internal/server, desc: only the composition root sees everything }
            - { pkg: example.com/app/internal/platform/apigen, desc: domain does not know the API }
            - { pkg: github.com/jackc/pgx, desc: domain has no SQL }
            - { pkg: net/http, desc: domain has no HTTP }
        app-layer:
          files: ["**/internal/*/app/**"]
          deny:
            - { pkg: example.com/app/internal/foos/api, desc: app does not know HTTP }
            - { pkg: example.com/app/internal/foos/jobs, desc: app does not know drivers }
            - { pkg: example.com/app/internal/server, desc: only the composition root sees everything }
        infra-layer:
          files: ["**/internal/*/infra/**"]
          deny:
            - { pkg: example.com/app/internal/foos/app, desc: infra does not call use cases }
            - { pkg: example.com/app/internal/foos/api, desc: infra does not know HTTP }
            - { pkg: example.com/app/internal/foos/jobs, desc: infra does not call drivers }
            - { pkg: example.com/app/internal/foos$, desc: infra does not call modules; wire.go passes ports }
            - { pkg: example.com/app/internal/server, desc: only the composition root sees everything }
  exclusions:
    generated: strict
    rules:
      - { path: _test\.go, linters: [gosec, noctx] }
formatters:
  enable: [gofmt]
```

Every new module repeats its lines in each list (`adding-go-modules`).

## internal/platform/apigen/oapi-codegen.yaml

```yaml
package: apigen
output: apigen.gen.go
generate:
  models: true
  std-http-server: true
  strict-server: true
  embedded-spec: true
output-options:
  skip-prune: true
```

## sqlc.yaml

```yaml
version: "2"
sql:
  - &module
    name: foos
    engine: postgresql
    schema: migrations
    queries: internal/foos/infra/queries.sql
    gen:
      go: &go
        package: db
        out: internal/foos/infra/db
        sql_package: pgx/v5
        emit_pointers_for_null_types: true
        emit_empty_slices: true
        overrides:
          - { db_type: uuid, go_type: string }
          - { db_type: uuid, nullable: true, go_type: { type: string, pointer: true } }
          - { db_type: timestamptz, go_type: time.Time }
          - { db_type: timestamptz, nullable: true, go_type: { import: time, type: Time, pointer: true } }
  # - <<: *module
  #   name: bars
  #   queries: internal/bars/infra/queries.sql
  #   gen: { go: { <<: *go, out: internal/bars/infra/db } }
```

## compose.yaml, Dockerfile, .env.example

```yaml
# Local development only.
services:
  postgres:
    image: postgres:17
    environment: { POSTGRES_PASSWORD: postgres }
    ports: ["5432:5432"]
    command: ["postgres", "-c", "shared_preload_libraries=pg_stat_statements"]
    healthcheck: { test: ["CMD-SHELL", "pg_isready -U postgres"], interval: 2s, retries: 30 }
  storage:            # any S3-compatible local server
    image: <s3-compatible image>
    ports: ["9000:9000"]
```

```dockerfile
FROM golang:1.25 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -tags release -trimpath -o /out/app ./cmd/app   # no fake providers compiled in

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/app /app
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/app"]
CMD ["api"]
```

`.env.example` lists every variable of `config.Config` with dev values and no real secret: `APP_ENV=local`, `APP_HTTP_ADDR=:8080`, `APP_DATABASE_URL=postgres://app_runtime:dev@localhost:5432/app`, `APP_MIGRATOR_DATABASE_URL=postgres://app_migrator:dev@localhost:5432/app`, `APP_SYSTEM_DATABASE_URL=postgres://app_system:dev@localhost:5432/app`, `APP_JWT_SECRET=<32+ chars>`, `APP_AUTH_PEPPER=<32+ chars>`. `.gitignore`: `.env`, `bin/`, `cover.out`.

## deploy/postgres/bootstrap.sql

```sql
-- Once per installation as a superuser, before the first `app migrate`.
-- psql -v migrator_password=… -v app_password=… -v system_password=… -f bootstrap.sql
-- The migrator owns the objects, so it grants on them without role membership or CREATEROLE.
CREATE ROLE app_migrator LOGIN PASSWORD :'migrator_password';
CREATE ROLE app_runtime  LOGIN PASSWORD :'app_password' NOBYPASSRLS;
CREATE ROLE app_system   LOGIN PASSWORD :'system_password' BYPASSRLS; -- global jobs only, own pool
CREATE DATABASE app OWNER app_migrator;
```

## migrations/00001_platform.sql and embed.go

```sql
-- +goose Up
CREATE SCHEMA platform;
GRANT USAGE ON SCHEMA platform TO app_runtime;
-- +goose StatementBegin
CREATE FUNCTION platform.current_tenant_id() RETURNS uuid LANGUAGE sql STABLE PARALLEL SAFE
    AS $$ SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid $$;
CREATE FUNCTION platform.refuse_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '% is append-only', TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME USING ERRCODE = 'insufficient_privilege';
END $$;
-- +goose StatementEnd
GRANT EXECUTE ON FUNCTION platform.current_tenant_id() TO app_runtime;

CREATE TABLE platform.idempotency_keys (
    user_id      uuid        NOT NULL,
    scope        text        NOT NULL,       -- acting tenant id from the resolved actor; '' when none
    key          uuid        NOT NULL,
    route        text        NOT NULL,
    body_hash    bytea       NOT NULL,
    response     bytea,
    created_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, scope, route, key) -- the key's scope: user, acting tenant, and route (operation id)
);
CREATE INDEX idempotency_keys_created_at ON platform.idempotency_keys (created_at);
GRANT SELECT, INSERT, UPDATE ON platform.idempotency_keys TO app_runtime;  -- Maintain (migrator) deletes expired rows; global table, reached only by the full key
```

```go
// Package migrations embeds the forward-only SQL migrations run by `app migrate`.
package migrations

import "embed"

// FS holds the migration files.
//
//go:embed *.sql
var FS embed.FS
```

## .githooks

`pre-commit`: `gofmt -l $(git diff --cached --name-only --diff-filter=ACM -- '*.go')` must print nothing; `go vet ./...`; `gitleaks protect --staged`. `pre-push`: `make check`.
