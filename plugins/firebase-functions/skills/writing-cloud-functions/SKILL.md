---
name: writing-cloud-functions
description: Add or change a callable or HTTP Cloud Function in a Firebase Functions backend — auth surface, Zod request schema, use case vs direct repository call, ApiModel mapping, options and secrets, export, integration tests. Use when adding an endpoint or changing its auth, validation, response, timeouts, memory, or secrets. Triggers, schedules, and task queues: writing-background-functions.
---

# Writing callable and HTTP functions

Policy — layers, handler shape, HttpsError mapping, ApiModels, security, client compatibility: the `architecture` rule. Middleware and options templates: `scaffolding-functions-backend`. Triggers, schedules, task queues: `writing-background-functions`.

## Workflow

1. **Contract first.** Name it verb + noun (`getFoo`, `listFoos`, `createFoo`, `updateFoo`, `deleteFoo`). New function or a change to an existing one? A change to name, region, request, response, or error semantics is a contract change: grep the clients and ask (the `architecture` rule → Client API compatibility).
2. **Auth surface**: authenticated user (default), owner of the entity (ownership check in the use case or an ownership middleware), admin (custom claim), internal (secret header or task queue), or public (intentional, rate-aware). `authMiddleware()` rejects anonymous users; pass `allowAnonymous: true` only where a guest may call it, and say why.
3. **Failing integration test** in the integration suite (`testing-cloud-functions`): call through the emulator with an Auth token; assert the response shape, the mapped error codes, and persisted state.
4. **Request schema**: `z.strictObject` from shared value schemas (ids, pagination, enums, ISO dates); `type Parameters = z.infer<typeof parametersSchema>`; length and size bounds on every string and array.
5. **Domain work**: a use case for two or more repositories, any rule, or any transaction; a direct repository call only for a single plain read or write. Domain failures throw typed `DomainError`s — the middleware maps them. A create that must not duplicate when the client retries after a timeout (payments, messages, anything with a side effect) takes a client-generated id (`IdentifierSchema`) and writes with `transaction.create`, returning the existing entity when that id is already there.
6. **Response**: `FooApiModelSchema` (Zod) with `type FooApiModel = z.infer<…>` and `fooApiModelFromEntity(entity, …)` in `endpoints/{feature}/model/fooApiModel.ts`; ISO dates; no raw entities. Lists are paged: `PageRequestSchema` in, `{items, nextCursor}` out (`listFoos` in `scaffolding-functions-backend` → `source-templates.md`).
7. **Options**: the shared region and defaults; explicit `timeoutSeconds`, `memory`, `maxInstances`, `secrets` only when they differ, each with a reason. A `timeoutSeconds` above the clients' callable timeout lets a client give up while the function still commits — keep it below. `enforceAppCheck` per the project's App Check plan (`securing-firebase-data` → App Check). Paid providers get a `maxInstances` cap and a quota plan.
8. **Export** from the exports entry point (`CLAUDE.md` → Project facts).
9. Lint, build, the integration suite (`CLAUDE.md` → Verification).

## Callable template

```typescript
const functionName = path.parse(__filename).name;

const parametersSchema = z.strictObject({
  fooId: IdentifierSchema,
  title: z.string().trim().min(1).max(FOO_TITLE_MAX_CHARS),
});
type Parameters = z.infer<typeof parametersSchema>;

export const updateFoo = onCall<Parameters, FooApiModel>(
  functionName,
  {region: FUNCTIONS_REGION},
  async (request) => {
    const foo = await updateFooUseCase({
      fooId: request.data.fooId,
      userId: requireUid(request),
      title: request.data.title,
    });
    return fooApiModelFromEntity(foo);
  },
  authMiddleware(),
  validateSchemaMiddleware(parametersSchema),
);
```

Read the caller through the project's helper (`requireUid(request)`), never `request.auth!`.

## HTTP functions

`onRequest` only when a callable does not fit (webhooks, redirects, public links, third-party callers). Verify the caller (provider signature over the raw body, a secret header, or an ID token), validate the body with Zod, set CORS explicitly (`securing-firebase-data` → CORS), return a status code per outcome, and never echo internal errors.

## Checklist

- [ ] Contract change grepped in clients and approved, or additive with the assumption stated
- [ ] Auth surface enforced (middleware, ownership in the use case, claims)
- [ ] Zod validation before domain work; bounds on every field
- [ ] Use case vs direct repository decision correct
- [ ] Typed domain errors; no `HttpsError` below `api`
- [ ] Options and secrets declared; limits justified
- [ ] Exported; integration tests green
