# Project configuration templates

Replace `foo` / `demo-foo` / `foo-stage` / `foo-prod`. Versions: install current releases (`npm install <pkg>@latest` once, at creation) and keep the major ranges `npm` writes.

## functions/package.json

```json
{
  "name": "foo-functions",
  "private": true,
  "main": "build/index.js",
  "engines": {"node": "24"},
  "scripts": {
    "lint": "eslint .",
    "typecheck": "tsc --noEmit",
    "build": "npm run lint && rm -rf build && tsc -p tsconfig.build.json",
    "build:emulator": "npm run build && bash ./scripts/build-emulator-mocks.sh",
    "test:unit": "bash ./scripts/test-unit.sh",
    "test:integration": "bash ./scripts/test-integration.sh",
    "test:rules": "bash ./scripts/test-rules.sh",
    "test": "npm run test:unit && npm run test:rules && npm run test:integration",
    "serve": "npm run build:emulator && firebase emulators:start --project demo-foo"
  },
  "_moduleAliases": {
    "@api": "build/api",
    "@core": "build/core",
    "@data": "build/data",
    "@domain": "build/domain",
    "@utils": "build/utils"
  },
  "dependencies": {
    "firebase-admin": "…",
    "firebase-functions": "…",
    "module-alias": "…",
    "zod": "…  (major 4; the templates' Zod typing assumes it)"
  },
  "devDependencies": {
    "@eslint/js": "…",
    "@types/node": "…",
    "eslint": "…",
    "eslint-config-prettier": "…",
    "eslint-plugin-prettier": "…",
    "firebase-tools": "…",
    "globals": "…",
    "prettier": "…",
    "typescript": "…",
    "typescript-eslint": "…",
    "vitest": "…",
    "@firebase/rules-unit-testing": "…",
    "firebase": "…",
    "@vitest/coverage-v8": "…"
  }
}
```

- `engines.node`: the newest LTS major the Cloud Functions runtime supports (`24` as of late 2026; check the runtime list); the same major in `.nvmrc` and CI.
- `serve` runs the local emulators against the `demo-foo` project with the provider mocks — never against a real project, where every non-emulated service would be live.
- `firebase-tools` as a dev dependency pins the emulator CLI for everyone; `npm run` puts it on `PATH`.
- Path aliases: TypeScript resolves `@core/*` at compile time; `module-alias` (registered first in `src/index.ts`) resolves them in the compiled build; vitest resolves them through `resolve.alias`.

## functions/tsconfig.json (typecheck and lint: src, tests, configs; no emit)

```json
{
  "compilerOptions": {
    "module": "commonjs",
    "target": "es2022",
    "lib": ["es2022"],
    "types": ["node"],
    "strict": true,
    "noImplicitReturns": true,
    "noUnusedLocals": true,
    "noFallthroughCasesInSwitch": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "noEmit": true,
    "paths": {
      "@api/*": ["./src/api/*"],
      "@core/*": ["./src/core/*"],
      "@data/*": ["./src/data/*"],
      "@domain/*": ["./src/domain/*"],
      "@utils/*": ["./src/utils/*"],
      "@test/*": ["./test/*"]
    }
  },
  "include": ["src/**/*.ts", "test/**/*.ts", "vitest.config.ts"]
}
```

ESLint's typed rules use the project service, which reads only files named `tsconfig.json` — so that file covers everything lint sees, tests included, and the emitting builds extend it:

- `tsconfig.build.json` (production build): `"extends": "./tsconfig.json"`, `"noEmit": false`, `"sourceMap": true`, `"rootDir": "src"`, `"outDir": "build"`, `"include": ["src"]`.
- `tsconfig.mocks.json` (emulator mocks build): `"extends": "./tsconfig.json"`, `"noEmit": false`, `"rootDir": "."`, `"outDir": ".tmp-emulator-build"`, `"include": ["src/**/*.ts", "test/mocks/**/*.ts"]`.

## functions/scripts/build-emulator-mocks.sh

```bash
#!/usr/bin/env bash
# Compiles test/mocks into build/test/mocks so the Functions emulator can load them.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
rm -rf .tmp-emulator-build build/test
npx tsc -p tsconfig.mocks.json
mkdir -p build/test
cp -R .tmp-emulator-build/test/mocks build/test/mocks
rm -rf .tmp-emulator-build
```

Mocks import production code through `@core/...`, which `module-alias` maps to `build/core` — the same module instances the functions use, so `setFooService` swaps the real factory.

## functions/eslint.config.js

```javascript
const eslint = require("@eslint/js");
const tseslint = require("typescript-eslint");
const prettier = require("eslint-plugin-prettier");
const prettierConfig = require("eslint-config-prettier");
const globals = require("globals");

const httpsModules = ["firebase-functions/https", "firebase-functions/v2/https"];

// Below `api`, HttpsError and the https module are off limits too. Import other layers through
// their alias, never a relative `../` path across a layer folder (the aliases are what this checks).
const layer = (files, forbidden, {https = false} = {}) => ({
  files,
  rules: {
    "no-restricted-imports": ["error", {
      paths: https ? [] : httpsModules.map((name) => ({name, message: "HttpsError and transport live only in api."})),
      patterns: forbidden.map((name) => ({
        group: [`@${name}/*`],
        message: `Dependencies point api → domain → data → core; this layer must not import @${name}.`,
      })),
    }],
  },
});

module.exports = tseslint.config(
  eslint.configs.recommended,
  ...tseslint.configs.recommended,
  prettierConfig,
  {
    plugins: {prettier},
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
      globals: {...globals.node, ...globals.es2022},
      parserOptions: {projectService: {allowDefaultProject: ["*.js"]}, tsconfigRootDir: __dirname},
    },
    rules: {
      "prettier/prettier": "error",
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-non-null-assertion": "error",
      "@typescript-eslint/consistent-type-assertions": ["error", {assertionStyle: "never"}],
      "@typescript-eslint/no-floating-promises": "error",
      "@typescript-eslint/switch-exhaustiveness-check": "error",
      "@typescript-eslint/no-unused-vars": ["error", {argsIgnorePattern: "^_", varsIgnorePattern: "^_"}],
    },
  },
  // One entry per folder: a later entry for the same rule replaces an earlier one.
  layer(["src/utils/**"], ["core", "data", "domain", "api", "test"]),
  layer(["src/core/**"], ["data", "domain", "api", "test"]),
  layer(["src/data/**"], ["domain", "api", "test"]),
  layer(["src/domain/**"], ["api", "test"]),
  layer(["src/api/**"], ["test"], {https: true}),
  {ignores: ["build/**", ".tmp-emulator-build/**", "coverage/**", "scripts/**", "eslint.config.js"]},
);
```

`assertionStyle: "never"` still allows `as const`. Lint runs on `test/` too: it is in `tsconfig.json`, which the project service reads.

## firebase.json

```json
{
  "functions": [
    {
      "source": "functions",
      "codebase": "default",
      "ignore": ["node_modules", ".git", "*.log", "test", "build/test", "coverage",
                 ".tmp-emulator-build", ".secret.local", ".env.local", ".env.demo-*", "*.test-bak"],
      "predeploy": ["npm --prefix \"$RESOURCE_DIR\" run build"]
    }
  ],
  "firestore": {"rules": "firestore.rules", "indexes": "firestore.indexes.json"},
  "storage": {"rules": "storage.rules"},
  "emulators": {
    "singleProjectMode": true,
    "auth": {"port": 9099},
    "functions": {"port": 5001},
    "firestore": {"port": 8080},
    "storage": {"port": 9199},
    "pubsub": {"port": 8085},
    "tasks": {"port": 9499},
    "ui": {"enabled": true}
  }
}
```

Emulators bind to localhost by default; bind `0.0.0.0` only when a device on the network must reach them, and never in CI.

## .firebaserc

```json
{"projects": {"stage": "foo-stage", "prod": "foo-prod"}}
```

No `default`: every command names its project (`--project stage`), so nothing reaches production by accident. Tests use `--project demo-foo`.

## Env and secret files (functions/)

| File | Committed | Loaded | Holds |
| --- | --- | --- | --- |
| `.env` | yes | every project | non-secret defaults (`MAX_INSTANCES=10`) |
| `.env.stage`, `.env.prod` | yes | that alias / project id | per-project values (`FOO_BASE_URL=…`) |
| `.env.demo-foo` | yes | the test project | test values, `TEST_SUITE=integration`, localhost callback URLs |
| `.env.local` | no (`.env.local.example` is) | emulator only, highest priority | personal emulator overrides |
| `.secret.local` | no (`.secret.local.example` is, with fake values) | emulator only | values for every `defineSecret` |

## functions/.gitignore

```
node_modules/
build/
.tmp-emulator-build/
coverage/
*.log
.secret.local
.env.local
*.test-bak
```

## functions/scripts/test-unit.sh

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
unset GOOGLE_APPLICATION_CREDENTIALS
export GCLOUD_PROJECT=demo-foo TEST_SUITE=unit
firebase emulators:exec --project demo-foo --config ../firebase.json --only firestore \
  "npx vitest run test/unit"
```

## functions/scripts/test-integration.sh

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
unset GOOGLE_APPLICATION_CREDENTIALS
export GCLOUD_PROJECT=demo-foo TEST_SUITE=integration

# Personal emulator overrides and secrets (maybe real keys) must not leak into the test run.
restore=()
for f in .env.local .secret.local; do
  if [[ -f $f ]]; then mv "$f" "$f.test-bak"; restore+=("$f"); fi
done
trap 'rm -f .secret.local; for f in ${restore[@]+"${restore[@]}"}; do mv "$f.test-bak" "$f"; done' EXIT
cp .secret.local.example .secret.local

npm run build:emulator
firebase emulators:exec --project demo-foo --config ../firebase.json \
  --only auth,firestore,functions,storage,pubsub,tasks \
  "npx vitest run test/integration"
```

Fresh emulators per run (no `--import`) keep suites independent.

## functions/scripts/test-rules.sh

```bash
#!/usr/bin/env bash
# Security rules tests (securing-firebase-data): Firestore and Storage emulators, client SDK contexts.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
unset GOOGLE_APPLICATION_CREDENTIALS
export GCLOUD_PROJECT=demo-foo TEST_SUITE=rules
firebase emulators:exec --project demo-foo --config ../firebase.json --only firestore,storage \
  "npx vitest run test/rules"
```

Rules tests live in `test/rules/` (`firestore.rules.test.ts`, `storage.rules.test.ts`) and use `@firebase/rules-unit-testing` with the `firebase` client SDK — the client view the rules guard, never the Admin SDK (which bypasses rules). They need no Functions build. `emulatorSafety.ts` accepts `TEST_SUITE=rules` (it asserts `FIREBASE_STORAGE_EMULATOR_HOST` for it too).

## CI (GitHub Actions shape; port to the project's CI)

```yaml
name: functions
on: [pull_request]
jobs:
  verify:
    runs-on: ubuntu-latest
    defaults: {run: {working-directory: functions}}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: {node-version-file: functions/.nvmrc, cache: npm, cache-dependency-path: functions/package-lock.json}
      - uses: actions/setup-java@v4          # the Firestore emulator needs a JDK
        with: {distribution: temurin, java-version: "21"}
      - uses: actions/cache@v4
        with: {path: ~/.cache/firebase/emulators, key: firebase-emulators-${{ hashFiles('functions/package-lock.json') }}}
      - run: npm ci
      - run: npm run build
      - run: npm run typecheck
      - run: npm run test:unit
      - run: npm run test:rules
      - run: npm run test:integration
```

CI needs no Firebase credentials: the `demo-` project never leaves the emulators. Deployment is a separate, human-approved job with its own credentials (workload identity), never part of the verify job.
