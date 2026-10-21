# Source templates

One feature (`Foo`) end to end, layer by layer. Paths are under `functions/src/`.

## index.ts — composition root

```typescript
import "module-alias/register";
import {setGlobalOptions} from "firebase-functions/v2";
import {FUNCTIONS_GLOBAL_OPTIONS} from "@api/config/functionsConfig";
import {testMode} from "@utils/testMode";

setGlobalOptions(FUNCTIONS_GLOBAL_OPTIONS);
_loadTestProviders();

export * from "./api";

function _loadTestProviders(): void {
  if (testMode.getTestSuite() === undefined) return;
  testMode.assertFunctionsEmulator({action: "loading test providers"});
  const mockAssemblyPath = "./test/mocks/mockAssembly"; // compiled by build:emulator, never deployed
  // The one documented lint exception in the backend: a runtime-only load of test code
  // that must not be a static import (production builds do not contain it).
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  require(mockAssemblyPath);
}
```

## utils/testMode.ts — the one test gate

```typescript
export const testMode = {
  isFunctionsEmulator(): boolean {
    return process.env.FUNCTIONS_EMULATOR === "true";
  },
  assertFunctionsEmulator(params: {action: string}): void {
    if (!testMode.isFunctionsEmulator()) {
      throw new Error(`${params.action} is only allowed in the Functions emulator`);
    }
  },
  getTestSuite(): "unit" | "integration" | undefined {
    const suite = process.env.TEST_SUITE;
    return suite === "unit" || suite === "integration" ? suite : undefined;
  },
};
```

## core/firebaseApp.ts

```typescript
import {getApps, initializeApp} from "firebase-admin/app";

// Every Admin SDK user imports this, so import order never matters.
export const firebaseApp = getApps()[0] ?? initializeApp();
```

## api/config/functionsConfig.ts

```typescript
import {defineInt} from "firebase-functions/params";
import type {GlobalOptions} from "firebase-functions/v2";

export const FUNCTIONS_REGION = "us-central1";

const MAX_INSTANCES = defineInt("MAX_INSTANCES", {default: 10});

export const FUNCTIONS_GLOBAL_OPTIONS = {
  region: FUNCTIONS_REGION,
  maxInstances: MAX_INSTANCES,
  memory: "256MiB",
  timeoutSeconds: 60, // clients' callable timeout stays longer (writing-cloud-functions)
} satisfies GlobalOptions;
```

## domain/error/domainError.ts

```typescript
export type DomainErrorCode =
  | "invalid-input"
  | "not-found"
  | "forbidden"
  | "conflict"
  | "precondition-failed"
  | "quota-exceeded";

/** Base of every error a catcher branches on. Messages are safe to show clients: ids, no internals. */
export abstract class DomainError extends Error {
  abstract readonly code: DomainErrorCode;

  constructor(message: string) {
    super(message);
    this.name = new.target.name;
  }
}

/** A list cursor that no longer resolves (its document was deleted): the client restarts from page one. */
export class PageCursorInvalidError extends DomainError {
  readonly code = "invalid-input";
  constructor(readonly cursor: string) {
    super("Invalid page cursor");
  }
}
```

`domain/usecase/foo/error/fooErrors.ts`:

```typescript
export class FooNotFoundError extends DomainError {
  readonly code = "not-found";
  constructor(readonly fooId: string) {
    super(`Foo '${fooId}' not found`);
  }
}

export class FooQuotaExceededError extends DomainError {
  readonly code = "quota-exceeded";
  constructor(readonly userId: string) {
    super("Foo limit reached");
  }
}
```

## api/common/middleware/toHttpsError.ts — the one mapping (`architecture` rule → API boundary)

```typescript
import {FunctionsErrorCode, HttpsError} from "firebase-functions/v2/https";
import {DomainError, DomainErrorCode} from "@domain/error/domainError";

// A ZodError here did not come from the request (validateSchemaMiddleware maps those): a converter
// or a provider response failed to parse — a server bug, so it falls through to `internal`.
export function toHttpsError(error: unknown): HttpsError {
  if (error instanceof HttpsError) return error;
  if (error instanceof DomainError) return new HttpsError(_httpsCode(error.code), error.message);
  return new HttpsError("internal", "Internal error");
}

function _httpsCode(code: DomainErrorCode): FunctionsErrorCode {
  switch (code) {
    case "invalid-input":
      return "invalid-argument";
    case "not-found":
      return "not-found";
    case "forbidden":
      return "permission-denied";
    case "conflict":
      return "already-exists";
    case "precondition-failed":
      return "failed-precondition";
    case "quota-exceeded":
      return "resource-exhausted";
  }
}
```

## api/common/middleware/onCallWithMiddleware.ts

```typescript
import {logger} from "firebase-functions/logger";
import {
  CallableFunction, CallableOptions, CallableRequest, onCall as firebaseOnCall,
} from "firebase-functions/v2/https";
import {getErrorMessage} from "@utils/getErrorMessage";
import {toHttpsError} from "./toHttpsError";

type Middleware<T> = (request: CallableRequest<T>) => void | Promise<void>;

export function onCall<T, R>(
  functionName: string,
  options: CallableOptions<T>,
  handler: (request: CallableRequest<T>) => Promise<R>,
  ...middlewares: Middleware<T>[]
): CallableFunction<T, Promise<R>> {
  return firebaseOnCall<T, Promise<R>>(options, async (request) => {
    const startedAt = Date.now();
    const uid = request.auth?.uid ?? null;
    try {
      for (const middleware of middlewares) {
        await middleware(request);
      }
      const result = await handler(request);
      logger.info(`${functionName} finished`, {uid, durationMs: Date.now() - startedAt});
      return result;
    } catch (error) {
      const httpsError = toHttpsError(error);
      const fields = {
        uid,
        appCheck: request.app ? "ok" : "missing",
        code: httpsError.code,
        durationMs: Date.now() - startedAt,
        cause: getErrorMessage(error),
      };
      // The stack lets Error Reporting group internal failures.
      if (httpsError.code === "internal") logger.error(`${functionName} failed`, {...fields, stack: error instanceof Error ? error.stack : undefined});
      else logger.warn(`${functionName} rejected`, fields);
      throw httpsError;
    }
  });
}
```

Never log `request.data`: payloads carry personal data. `appCheck` is the monitor-mode signal before `enforceAppCheck` is turned on (`securing-firebase-data` → App Check).

## api/common/middleware/authMiddleware.ts

```typescript
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";

export function authMiddleware(params?: {allowAnonymous?: boolean; requiredClaim?: string}) {
  return <T>(request: CallableRequest<T>): void => {
    const auth = request.auth;
    if (!auth) throw new HttpsError("unauthenticated", "Sign-in required");
    if (!params?.allowAnonymous && auth.token.firebase.sign_in_provider === "anonymous") {
      throw new HttpsError("permission-denied", "A full account is required");
    }
    if (params?.requiredClaim !== undefined && auth.token[params.requiredClaim] !== true) {
      throw new HttpsError("permission-denied", "Permission denied");
    }
  };
}

export function requireUid<T>(request: CallableRequest<T>): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign-in required");
  return uid;
}
```

The callable runtime already verified the ID token. Where a revoked session must be refused at once, add `await getAuth().verifyIdToken(auth.rawToken, true)` (one Auth call per request). App Check: `securing-firebase-data`.

## api/common/middleware/validateSchemaMiddleware.ts

```typescript
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {z} from "zod";

// The only place a ZodError becomes `invalid-argument`: it is the client's input that failed.
export function validateSchemaMiddleware<T>(schema: z.ZodType<T>) {
  return (request: CallableRequest<T>): void => {
    const parsed = schema.safeParse(request.data);
    if (!parsed.success) throw new HttpsError("invalid-argument", "Invalid request", z.flattenError(parsed.error));
    request.data = parsed.data;
  };
}
```

Templates target Zod 4, where `z.ZodType<T>` accepts any input type (needed for `.default()` fields). On Zod 3 write `z.ZodType<T, z.ZodTypeDef, unknown>`.

## core/db — registry, converter, versioned entity

`core/db/common/identifierSchema.ts` — every document id that crosses the API. A `/` would address a nested path through the wrong converter, so ids never contain one:

```typescript
export const IdentifierSchema = z.string().min(1).max(128).regex(/^[A-Za-z0-9_-]+$/);
```

`core/db/utils/withId.ts` and `firestoreDocumentMigrator.ts`:

```typescript
export type WithId<T> = T & {readonly id: string};
export type FirestoreDocumentMigrator = (data: DocumentData) => DocumentData;
```

`core/db/utils/createFirestoreConverter.ts`:

```typescript
export function createFirestoreConverter<T>(schema: z.ZodType<T>, migrator: FirestoreDocumentMigrator) {
  return {
    toFirestore(model: WithId<T>): T {
      const {id: _id, ...data} = model;
      return schema.parse(data);
    },
    fromFirestore(snapshot: QueryDocumentSnapshot): WithId<T> {
      const raw = snapshot.data();
      const latest = schema.safeParse(raw);
      const parsed = latest.success ? latest : schema.safeParse(migrator(Object.assign({}, raw)));
      if (!parsed.success) {
        throw new Error(`Unreadable '${snapshot.ref.path}': ${parsed.error.message}`);
      }
      return Object.assign({}, parsed.data, {id: snapshot.id});
    },
  };
}
```

`core/db/entity/foo/schema/v1.ts`, `latest.ts`, `migration.ts`:

```typescript
// v1.ts — immutable once shipped
export const FooStatusSchemaV1 = z.enum(["draft", "published"]);
export const FooEntitySchemaV1 = z.object({
  _version: z.literal(1),
  title: z.string().min(1).max(FOO_TITLE_MAX_CHARS),
  status: FooStatusSchemaV1,
  createdBy: IdentifierSchema,
  createdAt: z.instanceof(Timestamp),
  updatedAt: z.instanceof(Timestamp),
});

// latest.ts — the only file callers import schemas and types from
export const FooEntitySchema = FooEntitySchemaV1;
export type FooEntity = WithId<z.infer<typeof FooEntitySchema>>;
export type FooStatus = z.infer<typeof FooStatusSchemaV1>;

// migration.ts — pure; one block per hop, oldest first
export const FooMigrator: FirestoreDocumentMigrator = (data) => {
  if (data._version === undefined) data._version = 1;
  // if (data._version === 1) { data.summary = null; data._version = 2; }
  return data;
};
```

`core/db/firestoreDb.ts`:

```typescript
import {getFirestore, Transaction} from "firebase-admin/firestore";
import {firebaseApp} from "@core/firebaseApp";

const firestore = getFirestore(firebaseApp);

// Exported so triggers parse event snapshots the same way the registry reads documents.
export const fooConverter = createFirestoreConverter(FooEntitySchema, FooMigrator);

export const db = {
  runTransaction: <T>(update: (transaction: Transaction) => Promise<T>) => firestore.runTransaction(update),
  batch: () => firestore.batch(),
  bulkWriter: () => firestore.bulkWriter(),

  foos: firestore.collection("foos").withConverter(fooConverter),
  fooSettings: (fooId: string) =>
    firestore.doc(`foos/${fooId}/settings/${fooId}`).withConverter(
      createFirestoreConverter(FooSettingsEntitySchema, FooSettingsMigrator),
    ),
};
```

`core/db/index.ts` re-exports `db`, the latest schemas, and entity types — the `core` DB module other layers import.

## data/repository/fooRepository.ts

Template and naming: `creating-firestore-repositories`.

## core/foo — provider service

```typescript
// fooService.ts — contract + facade
export interface FooService {
  summarize(params: {apiKey: string; text: string}): Promise<FooSummary>;
}
export const FooService: FooService = {
  summarize: (params) => resolveFooService().summarize(params),
};

// acmeFooService.ts — named by provider; dependencies through the constructor
export class AcmeFooService implements FooService {
  constructor(private readonly config: {baseUrl: string; timeoutMs: number}) {}

  async summarize(params: {apiKey: string; text: string}): Promise<FooSummary> {
    // fetch with AbortSignal.timeout(this.config.timeoutMs);
    // map HTTP status → new FooServiceError("rate-limit" | "timeout" | "auth" | …)
  }
}

// fooServiceFactory.ts — the composition seam
let _fooService: FooService | undefined;

export function resolveFooService(): FooService {
  _fooService ??= new AcmeFooService({baseUrl: ACME_BASE_URL.value(), timeoutMs: 25_000});
  return _fooService;
}

export function setFooService(service: FooService): void {
  testMode.assertFunctionsEmulator({action: "setFooService"});
  _fooService = service;
}
```

`fooServiceError.ts`: `class FooServiceError extends Error` with `readonly code: FooServiceErrorCode` (a closed union).

## domain/usecase/foo

```typescript
// utils/getFooOrThrow.ts — the throwing read, owned by the Foo feature
export async function getFooOrThrow(params: {fooId: string}, transaction?: Transaction): Promise<FooEntity> {
  const foo = await FooRepository.getById({fooId: params.fooId}, transaction);
  if (!foo) throw new FooNotFoundError(params.fooId);
  return foo;
}

// createFooUseCase.ts — one unit of work
export async function createFooUseCase(params: {userId: string; title: string}): Promise<FooEntity> {
  return db.runTransaction(async (transaction) => {
    const existing = await FooRepository.getAllByCreatedBy(
      {createdBy: params.userId, limit: FOO_LIMIT_PER_USER},
      transaction,
    );
    if (existing.length >= FOO_LIMIT_PER_USER) throw new FooQuotaExceededError(params.userId);
    const now = Timestamp.now();
    return FooRepository.createWithinTransaction(transaction, {
      foo: {
        _version: 1,
        id: FooRepository.generateId(),
        title: params.title,
        status: "draft",
        createdBy: params.userId,
        createdAt: now,
        updatedAt: now,
      },
    });
  });
}
```

`listFoosUseCase.ts` — a paged read (page rules live here, not in the handler):

```typescript
export async function listFoosUseCase(params: {
  userId: string;
  cursor?: string;
  limit: number;
}): Promise<{items: FooEntity[]; nextCursor: string | null}> {
  const page = await FooRepository.getPageByCreatedBy({
    createdBy: params.userId,
    limit: params.limit + 1, // one extra tells whether another page exists
    startAfterId: params.cursor,
  });
  if (page === null) throw new PageCursorInvalidError(params.cursor ?? "");
  const items = page.slice(0, params.limit);
  const nextCursor = page.length > params.limit ? items[items.length - 1].id : null;
  return {items, nextCursor};
}
```

## api/common/validation/schemas/pageSchemas.ts — the paged contract

```typescript
export const PageRequestSchema = z.strictObject({
  cursor: IdentifierSchema.optional(),
  limit: z.number().int().min(1).max(50).default(20),
});

export function pageApiModelSchema<T extends z.ZodType>(itemSchema: T) {
  return z.object({items: z.array(itemSchema), nextCursor: z.string().nullable()});
}
```

## api/endpoints/foo

ApiModels are Zod schemas; the type is inferred, and tests parse responses with the same schema.

```typescript
// model/fooApiModel.ts
export const FooApiModelSchema = z.object({
  id: z.string(),
  title: z.string(),
  status: FooStatusSchema,
  createdAt: z.iso.datetime(),
});
export type FooApiModel = z.infer<typeof FooApiModelSchema>;

export const FooPageApiModelSchema = pageApiModelSchema(FooApiModelSchema);
export type FooPageApiModel = z.infer<typeof FooPageApiModelSchema>;

export function fooApiModelFromEntity(entity: FooEntity): FooApiModel {
  return {
    id: entity.id,
    title: entity.title,
    status: entity.status,
    createdAt: entity.createdAt.toDate().toISOString(),
  };
}

// createFoo.ts
const functionName = path.parse(__filename).name;

const parametersSchema = z.strictObject({
  title: z.string().trim().min(1).max(FOO_TITLE_MAX_CHARS),
});
type Parameters = z.infer<typeof parametersSchema>;

export const createFoo = onCall<Parameters, FooApiModel>(
  functionName,
  {region: FUNCTIONS_REGION},
  async (request) => {
    const foo = await createFooUseCase({userId: requireUid(request), title: request.data.title});
    return fooApiModelFromEntity(foo);
  },
  authMiddleware(),
  validateSchemaMiddleware(parametersSchema),
);
```

```typescript
// listFoos.ts — paged list: request {cursor?, limit}, response {items, nextCursor}
const parametersSchema = PageRequestSchema;
type Parameters = z.infer<typeof parametersSchema>;

export const listFoos = onCall<Parameters, FooPageApiModel>(
  path.parse(__filename).name,
  {region: FUNCTIONS_REGION},
  async (request) => {
    const page = await listFoosUseCase({
      userId: requireUid(request),
      cursor: request.data.cursor,
      limit: request.data.limit,
    });
    return {items: page.items.map((foo) => fooApiModelFromEntity(foo)), nextCursor: page.nextCursor};
  },
  authMiddleware(),
  validateSchemaMiddleware(parametersSchema),
);
```

Wire names: `getFoo`, `listFoos`, `createFoo`, `updateFoo`, `deleteFoo` (the `architecture` rule → API boundary). `api/index.ts`: `export * from "./endpoints/foo/createFoo";` — one line per function, grouped by feature.
