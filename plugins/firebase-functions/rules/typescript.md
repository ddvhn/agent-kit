---
description: TypeScript standards — no any, no type assertions, modern syntax, exhaustive unions, params objects, private-helper prefix, naming
paths:
  - "**/*.ts"
---

# TypeScript

- Never use `any` (annotation, cast, generic, return). Prefer interfaces, Zod-inferred types, `unknown` + narrowing, unions, utility types.
- Do not force type compatibility with assertions (`value as Foo`, `<Foo>value`, `as unknown as Foo`) or non-null assertions (`foo!`). Establish types at compile time through inference, annotations, `satisfies`, narrowing / type guards, discriminated unions, generic constraints, or runtime parsing (Zod) at trust boundaries. `as const` is allowed. The narrowest assertion only at an unavoidable compiler or untyped-library boundary after validating the data; never to hide a real mismatch.
- Modern syntax: `const` / `let`, optional chaining, nullish coalescing, `async` / `await`, ES modules, `satisfies` / `as const` when helpful. No floating promises: `await`, return, or mark a deliberate fire-and-forget with `void`.
- Unions are closed: `switch` over a union or error `code` is exhaustive (no `default` that swallows a new member), so adding a member fails the build where it must be handled.
- Explicit types on exported params and returns. `readonly` for shared or config data that is not mutated.
- Object arguments: name the parameter `params` and inline its type on the function. A named `FooParams` type only when the shape is reused across modules or is a public contract (Zod schemas always get named types).
- Prefix with `_` only module-private helper functions, private class methods, and mutable module holders (`_buildFoo`, `_executeRequest`, `_fooService`). Do not prefix declarative module constants: function names, `defineSecret` / `defineString` bindings, Zod schemas, prompt or config literals. Declare private helpers after the file's exported declarations.
- Names: a function returning a named type carries that type (core `minimal-change`), e.g. `mockFooEntity` → `FooEntity`. Files are named for their main export in camelCase (`fooRepository.ts`, `createFooUseCase.ts`, `fooApiModel.ts`). Services, factories, and helpers: the `architecture` rule → Provider services.
- No `@ts-ignore` / `@ts-nocheck`. `@ts-expect-error` only with a one-line justification and minimal scope.
- Follow the project's ESLint / Prettier config; if it forbids object or array spread, do not use it.
