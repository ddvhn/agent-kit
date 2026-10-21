---
name: securing-firebase-data
description: Firestore and Storage security rules, rules unit tests, Firestore indexes, App Check, and CORS for a Firebase Functions backend. Kit default is deny-all — clients never read or write Firestore or Storage directly; every access goes through functions — unless a documented exception (public read of published content, uploads to the user's own path). Use when creating or changing firestore.rules, storage.rules, firestore.indexes.json, adding a direct client access path, enabling App Check, or exposing an HTTP function to browsers.
---

# Securing Firebase data

Server-side policy (auth middleware, claims, secrets, what responses may contain): the `architecture` rule → Security. This skill covers what clients can reach without a function.

## Default: deny all

Clients reach data only through functions. The Admin SDK bypasses rules, so functions are unaffected.

```
// firestore.rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if false;
    }
  }
}

// storage.rules
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read, write: if false;
    }
  }
}
```

## Exceptions

A direct client path is a security boundary and a persistence contract: ask first (working agreement → When to ask first), then record it — the rule block, a comment naming why, the client that uses it, and an entry in the repository's rules. Common, acceptable exceptions:

| Exception | Rule shape |
| --- | --- |
| Public read of published content (no secrets or personal fields in the document) | `match /foos/{fooId} { allow read: if resource.data.status == "published"; }` — list queries must filter on the same field, or they are denied |
| A user reads their own document | `allow read: if request.auth != null && request.auth.uid == userId;` |
| A user uploads to their own Storage path | see below |
| Real-time listener on a status document the backend writes | read-only, owner-scoped as above |

Writes from clients are the rare case: business invariants live in the backend (core `architecture-principles` → Offline-first). Prefer a callable over a client write rule.

```
// storage.rules — uploads to the caller's own folder, bounded size and type
match /b/{bucket}/o {
  match /users/{userId}/uploads/{fileName} {
    allow read: if request.auth != null && request.auth.uid == userId;
    allow create: if request.auth != null
      && request.auth.uid == userId
      && request.resource.size < 10 * 1024 * 1024
      && request.resource.contentType.matches('image/.*');
  }
}
```

After an upload, a function (`onObjectFinalized` or a "finish upload" callable) validates the file and links it to the entity; the client never writes the reference itself.

Rule hygiene: deny by default and allow narrowly (`get` / `list` / `create` / `update` / `delete` instead of `write` when they differ); validate `request.resource.data` keys and types on any allowed write (`keys().hasOnly([...])`); no rule reads (`get()` / `exists()`) on hot list paths — each one is billed.

## Rules unit tests

Every rules change ships with tests in `test/rules/`, run by `npm run test:rules` (Firestore and Storage emulators; script and dev dependencies `@firebase/rules-unit-testing` + `firebase`: `scaffolding-functions-backend` → `project-config.md`). Tests use client SDK contexts — the Admin SDK bypasses rules.

```typescript
const testEnv = await initializeTestEnvironment({
  projectId: "demo-foo",
  firestore: {rules: readFileSync("../firestore.rules", "utf8")},
  storage: {rules: readFileSync("../storage.rules", "utf8")},
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
});
afterAll(() => testEnv.cleanup());

it("denies everything to signed-in users by default", async () => {
  const db = testEnv.authenticatedContext("user-1").firestore();
  await assertFails(getDoc(doc(db, "foos/foo-1")));
  await assertFails(setDoc(doc(db, "foos/foo-1"), {title: "Foo"}));
});

it("lets anyone read a published foo", async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "foos/foo-1"), {status: "published"});
  });
  await assertSucceeds(getDoc(doc(testEnv.unauthenticatedContext().firestore(), "foos/foo-1")));
});
```

Storage (`firebase/storage`):

```typescript
it("lets a user upload a small image to their own folder only", async () => {
  const storage = testEnv.authenticatedContext("user-1").storage();
  const image = new Uint8Array([0xff, 0xd8, 0xff]);
  await assertSucceeds(uploadBytes(ref(storage, "users/user-1/uploads/a.jpg"), image, {contentType: "image/jpeg"}));
  await assertFails(uploadBytes(ref(storage, "users/user-2/uploads/a.jpg"), image, {contentType: "image/jpeg"}));
  await assertFails(uploadBytes(ref(storage, "users/user-1/uploads/a.txt"), image, {contentType: "text/plain"}));
});

it("denies everything else in Storage", async () => {
  const storage = testEnv.authenticatedContext("user-1").storage();
  await assertFails(getBytes(ref(storage, "foos/foo-1/cover.jpg")));
});
```

Cover, per exception: allowed for the intended caller; denied for anonymous, for another user, for a wrong shape or size; and the deny-all default for an unrelated path.

## Indexes

- `firestore.indexes.json` is the source of truth, committed and deployed with the rules. Every composite query (equality + range, multiple `orderBy`, `array-contains` + filter, collection group) adds its index in the same change as the query.
- The emulator does not enforce indexes: a missing one fails only in a deployed project, with `FAILED_PRECONDITION` and a console link. Review every new query for its index.
- Field overrides: exempt large arrays, maps, and long strings that are never queried (`fieldOverrides` with empty `indexes`) — it cuts write cost and avoids index-entry limits; also exempt monotonically increasing fields written at a high rate.
- Drift: compare with the deployed set using `firebase firestore:indexes --project stage` (read-only); never delete an index the deployed code still uses.

## App Check

- Callables: `enforceAppCheck: true` in the options once every client ships App Check (roll out in monitor mode first: check `request.app` and log, then enforce). Expensive or abuse-prone callables also set `consumeAppCheckToken: true` (replay protection; clients request limited-use tokens).
- HTTP functions: verify the `X-Firebase-AppCheck` header with `getAppCheck().verifyToken(...)` before any work.
- Firestore and Storage: enforce App Check in the console only for the exceptions above; deny-all needs nothing.
- The emulators do not prove App Check: verify on stage with a debug token. Enabling enforcement is a client-compatibility change (old app builds without App Check break) — ask first.

## CORS for HTTP functions

- Callables handle CORS themselves; leave the default unless a browser origin must be restricted (`cors: [origins]`).
- `onRequest` used from browsers: `cors: ["https://app.example.com", /\.example\.com$/]` — an explicit list, never `true` or `"*"` for an endpoint that uses credentials or cookies. Server-to-server endpoints (webhooks) set no CORS.
- Storage buckets read from browsers (signed URLs, direct downloads): a bucket CORS config (`cors.json`, applied with `gcloud storage buckets update --cors-file` by a human) that lists the app origins and only the needed methods — not `"*"` with write methods.

## Checklist

- [ ] Deny-all default in both rules files
- [ ] Every exception approved, commented, recorded in the repository's rules, and covered by allow and deny tests
- [ ] New queries have their indexes; unqueried large fields exempted
- [ ] App Check rollout planned (monitor → enforce) and approved
- [ ] HTTP CORS lists explicit origins
- [ ] Rules and indexes deployed by a human (`firebase deploy --only firestore,storage`)
