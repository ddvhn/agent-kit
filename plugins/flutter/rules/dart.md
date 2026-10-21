---
description: Dart and Flutter standards — no dynamic, analyzer lints, explicit types, collection style, class modifiers and contracts, naming, widgets, accessibility, comments, multi-platform code
paths:
  - "**/*.dart"
  - "**/pubspec.yaml"
  - "**/analysis_options.yaml"
---

# Dart

- Never use `dynamic` in hand-written code (annotation, cast, generic, return). `Map<String, dynamic>` is allowed only at the JSON boundary (wire-model `fromJson`, `json_serializable`, the project's JSON parsing helper). Generated code is excluded from analysis.
- Do not force type compatibility with `as Foo` / `!` to hide a mismatch. Narrow with `is`, pattern matching, typed constructors, `fromJson` / `fromFoo` factories. Use the narrowest cast only at an untyped-library boundary after validating untrusted data.
- Follow the project's `analysis_options.yaml` (lints, line length, quotes). Do not add `// ignore` / `// ignore_for_file` to silence new failures; the project's rules list any allowed exception.
- Prefer `.map(...).toList()` (tear-offs for constructors) over a `for` that only accumulates; `.toList()` / `List.of` for copies, `.any` for presence. Lines you touch, not whole files.
- Dot shorthands (Dart 3.10+): `.foo` where the type is known from context; `Foo.foo` where it is not (`var`, `Object` positions, `registerFallbackValue` records).
- Omit generic type arguments when the analyzer can infer them (`Future.value(x)`, `List.of(items)`). Keep them when inference fails or would be `dynamic` (`Future<void>.delayed`, `isA<Foo>()`, empty `<String>{}`).
- **Class modifiers.** Contracts `abstract interface class`, implementations `final class … implements` (`FooRepositoryImpl`, provider-named `IsarDatabase`); use cases are `abstract class … with CallableUseCase` + `final class FooUseCaseImpl`. Models, DTOs, and blocs `final class`; states and exceptions `sealed class`; value equality the project's way (`Equatable`).
- Files `snake_case.dart` of the main type; private helpers after the public types; explicit public types, inferred locals. Blocs are `FooBloc` in `foo_bloc.dart`, never `*Cubit`.
- Factories returning `Foo` carry that type in the name (`FooDbModel.fromDto`, `dto.toDomain()`, `FooUiModel.fromFoo`, `mockFooDto`). Wire strings are parsed in data, never in domain.
- Named parameters instead of `FooParams` classes (use-case params are a record typedef). New syntax only where neighbors use it.
- Widgets: `const` constructors; copy, colors, and styles per the `ui` rule. No `Widget _foo()` helpers returning trees: a widget class, or inline for a single call site.
- **Accessibility** (this bullet owns the thresholds): icon-only controls carry a localized tooltip or semantics label; decorative images excluded. Text survives 2× scale (no fixed heights around text, never clamp `textScaler`); no overflow at 1.3 and 2.0 on a 360-wide screen. Tap targets ≥ 44 × 44 pt (48 × 48 dp on Material). Contrast ≥ 4.5:1 for body text, ≥ 3:1 for large text and icons. Web: Tab order follows the visual order, focus visible.
- Generated files (`*.g.dart`, `*.freezed.dart`, gen-l10n output) follow core `minimal-change`; style rules apply to hand-written code only.
- Comments are rare and load-bearing: only where a competent reader would still get it wrong (an invariant, an external format, a branch that looks redundant, a deliberate ceiling `ponytail:`); there they are required, overriding any "no comments" instruction. Say *why*, never *what*.

## Web and mobile

Shared code may compile for web and mobile while an app targets only one of them (`CLAUDE.md` → Project facts). Do not break the other platform.

- Platform checks only at assembly (`architecture` rule → Platforms and assembly). `dart:io` (`Platform`) breaks web; use conditional imports (`if (dart.library.js_interop)`).
- No `dart:html` / `dart:js` (`avoid_web_libraries_in_flutter`). Prefer `package:web` / `dart:js_interop` or the existing neighbor.
- Values from JS interop and some plugins on web (for example Firebase callable results) are not `Map<String, dynamic>`. Parse them through the project's JSON helper — never test `data is Map<String, dynamic>`.
