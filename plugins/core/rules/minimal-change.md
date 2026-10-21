---
description: Minimal-change rule — the smallest correct change, reuse before inventing, root-cause fixes, scope
---

# Minimal change

Lazy means efficient, not careless. The best code is the code never written.

- **Understand first**, then stop at the first rung that holds: not needed (YAGNI) → already in this codebase → standard library / SDK → platform feature → installed dependency → one line → the minimum new code. No new dependency if avoidable; no abstractions or boilerplate nobody asked for. Deletion over addition, boring over clever, fewest files.
- **Smallest diff in the right place.** Bug fix = root cause: grep every caller of the function you touch and fix the shared function once.
- **Reuse names and concepts** already in the codebase; do not invent parallel terms (`FooProducer` beside `FooService`). A function returning a named type carries that type in its name.
- **Verify before inventing behavior.** Soft guards in old code are not product modes; trace real callers.
- **One call site → do not extract.** Extract only when a second real caller appears. The contracts the architecture requires (repository interfaces, use cases with a rule behind them) are not speculative abstractions — they stay even with one implementation.
- **Minimum stored state.** Derive instead of adding a flag or field.
- **Match neighbor error style** before inventing error types; ask when the client-visible code must change.
- **Pass through already-shaped params**; do not rebuild them at every layer.
- **Preserve existing comments and step labels** unless asked. Rename for accuracy when a name lies; not for taste.
- **Mark deliberate ceilings** with a `ponytail:` comment naming the limit and the upgrade path.
- **Not lazy about**: understanding the problem, validation at trust boundaries, error handling that prevents data loss, security, accessibility, anything explicitly requested. Non-trivial logic leaves the smallest test that fails if the logic breaks.
- Scope = what was asked. No drive-by refactors, no mass-fixing legacy. Never hand-edit generated files — change the input and re-run the generator.
- Classify failures with named error types or codes; never branch on error message text. Throw the typed error at the source; catchers map the type.
