# Test harness templates

Paths are under `functions/`. Policy: the `testing` rule; authoring: `testing-cloud-functions`.

## vitest.config.ts

```typescript
import path from "node:path";
import {defineConfig} from "vitest/config";

const integration = process.env.TEST_SUITE === "integration";

export default defineConfig({
  resolve: {
    alias: {
      "@api": path.resolve(__dirname, "src/api"),
      "@core": path.resolve(__dirname, "src/core"),
      "@data": path.resolve(__dirname, "src/data"),
      "@domain": path.resolve(__dirname, "src/domain"),
      "@utils": path.resolve(__dirname, "src/utils"),
      "@test": path.resolve(__dirname, "test"),
    },
  },
  test: {
    environment: "node",
    pool: "forks",
    fileParallelism: false, // one emulator, shared state: files run one at a time
    testTimeout: integration ? 45_000 : 10_000,
    hookTimeout: integration ? 30_000 : 15_000,
    setupFiles: ["test/utils/setup/emulatorSafety.ts"],
    include: ["test/**/*.test.ts"],
    coverage: {provider: "v8", include: [/* gated files, e.g. "src/data/repository/fooRepository.ts" */]},
  },
});
```

## test/utils/setup/emulatorSafety.ts

```typescript
import {getApps, initializeApp} from "firebase-admin/app";

export const TEST_PROJECT_ID = "demo-foo";

function _assertLocalhost(name: string): void {
  const value = process.env[name];
  if (!value || !/^(127\.0\.0\.1|localhost):\d+$/.test(value)) {
    throw new Error(`${name} must point to a localhost emulator, got '${value ?? ""}'`);
  }
}

if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  throw new Error("Unset GOOGLE_APPLICATION_CREDENTIALS: tests never use real credentials");
}
if (process.env.GCLOUD_PROJECT !== TEST_PROJECT_ID) {
  throw new Error(`Tests run only against '${TEST_PROJECT_ID}', got '${process.env.GCLOUD_PROJECT ?? ""}'`);
}
_assertLocalhost("FIRESTORE_EMULATOR_HOST");
if (process.env.TEST_SUITE === "integration") _assertLocalhost("FIREBASE_AUTH_EMULATOR_HOST");
if (process.env.TEST_SUITE === "integration" || process.env.TEST_SUITE === "rules") {
  _assertLocalhost("FIREBASE_STORAGE_EMULATOR_HOST");
}

if (getApps().length === 0) {
  initializeApp({projectId: TEST_PROJECT_ID, storageBucket: `${TEST_PROJECT_ID}.appspot.com`});
}
```

## test/utils/resetEmulatorState.ts

```typescript
export async function resetEmulatorState(): Promise<void> {
  await _delete(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${TEST_PROJECT_ID}/databases/(default)/documents`);
  if (process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    await _delete(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/emulator/v1/projects/${TEST_PROJECT_ID}/accounts`);
  }
  if (process.env.FIREBASE_STORAGE_EMULATOR_HOST) {
    await getStorage().bucket().deleteFiles({force: true});
  }
}

async function _delete(url: string): Promise<void> {
  const response = await fetch(url, {method: "DELETE"});
  if (!response.ok && response.status !== 404) {
    throw new Error(`Emulator reset failed: ${response.status} ${url}`);
  }
}
```

Call it in `beforeEach` of every suite (unit and integration).

## test/utils/authToken.ts

```typescript
/** An ID token for `uid` from the Auth emulator; `claims` become custom claims. */
export async function createAuthIdToken(uid: string, claims?: Record<string, unknown>): Promise<string> {
  const customToken = await getAuth().createCustomToken(uid, claims);
  const response = await fetch(
    `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake-api-key`,
    {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify({token: customToken, returnSecureToken: true})},
  );
  const body: unknown = await response.json();
  const parsed = z.object({idToken: z.string()}).safeParse(body);
  if (!response.ok || !parsed.success) throw new Error(`Auth emulator sign-in failed: ${response.status}`);
  return parsed.data.idToken;
}
```

An anonymous token: `POST …/v1/accounts:signUp?key=fake-api-key` with `{returnSecureToken: true}`.

## test/utils/callableClient.ts

```typescript
const CallableResponseSchema = z.union([
  z.object({result: z.unknown()}),
  z.object({error: z.object({status: z.string(), message: z.string()})}),
]);

export async function callCallable(params: {
  functionName: string;
  data: unknown;
  idToken?: string;
}): Promise<{status: number; body: z.infer<typeof CallableResponseSchema>}> {
  const headers: Record<string, string> = {"Content-Type": "application/json"};
  if (params.idToken) headers.Authorization = `Bearer ${params.idToken}`;
  const response = await fetch(
    `http://127.0.0.1:5001/${TEST_PROJECT_ID}/${FUNCTIONS_REGION}/${params.functionName}`,
    {method: "POST", headers, body: JSON.stringify({data: params.data})},
  );
  return {status: response.status, body: CallableResponseSchema.parse(await response.json())};
}
```

Assertion helpers beside it: `expectCallableResult(response, FooApiModelSchema)` parses `result` with the ApiModel's own Zod schema (exported from `api/endpoints/foo/model/fooApiModel.ts` — `source-templates.md`), so a response-shape change fails the test; `expectCallableError(response, "NOT_FOUND")` checks `error.status`. Callable error statuses are upper snake case (`INVALID_ARGUMENT`, `PERMISSION_DENIED`).

## test/utils/waitUntil.ts

```typescript
export async function waitUntil<T>(probe: () => Promise<T | undefined>, timeoutMs = 10_000): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const value = await probe();
    if (value !== undefined) return value;
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  throw new Error(`waitUntil timed out after ${timeoutMs} ms`);
}
```

For triggers and task handlers: poll the persisted effect, never sleep a fixed time.

## test/mocks/mockAssembly.ts — the mock composition root

```typescript
testMode.assertFunctionsEmulator({action: "test provider assembly"});

setFooService(new MockFooService());
// one line per provider seam; the project's list lives in its repository rules
```

`test/mocks/core/foo/mockFooService.ts`: `class MockFooService implements FooService` returning deterministic results, with hooks for error branches and races (`failWith(code)`, `delayMs`) that a test sets through an emulator-only control (a document the mock reads, or an internal test callable compiled only into the emulator build).

## test/mocks/foo/mockFooEntity.ts — builder

```typescript
export function mockFooEntity(overrides?: Partial<FooEntity>): FooEntity {
  const now = Timestamp.now();
  const base: FooEntity = {
    _version: 1,
    id: db.foos.doc().id,
    title: "Foo",
    status: "draft",
    createdBy: "user-1",
    createdAt: now,
    updatedAt: now,
  };
  return Object.assign(base, overrides);
}
```

## First tests

Vitest globals are off: every test file imports `describe`, `it`, `expect`, and hooks from `"vitest"` (omitted below).

```typescript
// test/unit/data/repository/fooRepository.test.ts
describe("FooRepository.getById", () => {
  beforeEach(resetEmulatorState);

  it("returns null for a missing foo", async () => {
    expect(await FooRepository.getById({fooId: "missing"})).toBeNull();
  });

  it("reads inside a transaction", async () => {
    const foo = mockFooEntity();
    await db.foos.doc(foo.id).set(foo);
    const read = await db.runTransaction((transaction) => FooRepository.getById({fooId: foo.id}, transaction));
    expect(read).toEqual(foo);
  });
});

// test/integration/api/endpoints/foo/createFoo.test.ts
describe("createFoo", () => {
  beforeEach(resetEmulatorState);

  it("rejects a caller without a token", async () => {
    const response = await callCallable({functionName: "createFoo", data: {title: "Foo"}});
    expectCallableError(response, "UNAUTHENTICATED");
  });

  it("creates a draft foo", async () => {
    const idToken = await createAuthIdToken("user-1");
    const response = await callCallable({functionName: "createFoo", data: {title: "Foo"}, idToken});
    const foo = expectCallableResult(response, FooApiModelSchema);
    expect(foo.status).toBe("draft");
    expect((await FooRepository.getById({fooId: foo.id}))?.createdBy).toBe("user-1");
  });
});

// test/integration/api/endpoints/foo/listFoos.test.ts
describe("listFoos", () => {
  beforeEach(resetEmulatorState);

  it("pages with nextCursor until null", async () => {
    for (const title of ["a", "b", "c"]) {
      const foo = mockFooEntity({title, createdBy: "user-1"});
      await db.foos.doc(foo.id).set(foo);
    }
    const idToken = await createAuthIdToken("user-1");
    const first = expectCallableResult(
      await callCallable({functionName: "listFoos", data: {limit: 2}, idToken}),
      FooPageApiModelSchema,
    );
    expect(first.items).toHaveLength(2);
    expect(first.nextCursor).toBe(first.items[1].id);
    const second = expectCallableResult(
      await callCallable({functionName: "listFoos", data: {limit: 2, cursor: first.nextCursor}, idToken}),
      FooPageApiModelSchema,
    );
    expect(second.items).toHaveLength(1);
    expect(second.nextCursor).toBeNull();
  });

  it("rejects a cursor whose document is gone", async () => {
    const idToken = await createAuthIdToken("user-1");
    const response = await callCallable({functionName: "listFoos", data: {limit: 2, cursor: "deleted-id"}, idToken});
    expectCallableError(response, "INVALID_ARGUMENT");
  });
});
```
