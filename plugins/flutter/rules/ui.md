---
description: Flutter UI — platform-native look on a 4 px grid, one MaterialApp.router root with a ThemeData per platform from design tokens, AppThemeX screen themes, Adaptive* widgets instead of platform branches, shared UI in common/, skeletons only for loading data, typed go_router with one adaptive page helper, every static string through the localization package
paths:
  - "**/*.dart"
  - "**/*.arb"
---

# UI

The app's design language: the project UI skill or `.claude/rules/` (`CLAUDE.md` → Project facts). Mechanics: `theming-flutter-apps`, `building-adaptive-widgets`, `adding-flutter-routes`, `localizing-flutter-apps`.

## Look and theme

- Platform quality on every screen: standard components and gestures first (Cupertino feel on iOS, Material on Android, hover, cursors, and focus on web); a custom component only when none fits, added to the project UI skill. Spacing, radii, and sizes from tokens on a 4 px grid.
- One root everywhere: `MaterialApp.router`, never `CupertinoApp`. One factory `makeTheme(platform:, brightness:)` builds the `ThemeData` from tokens; the platform it carries (`AppThemeX.platform`) is what widgets, tests, and goldens read.
- Tokens are the single source of values; when the design keeps a token file, the Dart (and CSS) tokens are generated from it.
- Each screen and shared component reads its own `AppThemeX` entry once per `build`; never raw tokens, hex values, `Colors.*`, or ad-hoc `TextStyle`s. Light and dark ship unless the design is light-only.

## Widgets

- Where Cupertino and Material differ, screens use one thin `Adaptive*` widget from `ui/lib/src/common/widgets/adaptive/`; screens never branch on the platform. No `flutter_platform_widgets`.
- Shared UI lives in `ui/lib/src/common/`; a widget used by one feature stays in it until a second feature needs it.
- One primary action per screen. Color never carries meaning alone; unknown server values render a neutral fallback.
- Static content (app bar, titles, labels, frames) renders at once; only bloc data gets a skeleton (`skeletonizer`), and only while there is no payload. Cached data stays on screen while it refreshes; a failed refresh is a notice, never a wipe. A spinner only inside a pressed button or pull-to-refresh, never full screen.
- An action that needs the network stays visible offline, disabled, with a "needs network" hint.

## Navigation

Fully typed `go_router` (`go_router_builder`): every screen, sheet, and modal is a route class; navigate only through route classes, never string paths or `$extra`; one global `redirect`. Every page comes from the adaptive page helper (native pushes on iOS and Android, no transition and real URLs on web). An app on another style keeps it unless asked.

## Copy

Every static string a user can see goes through the shared `localization` package (`context.strings.fooTitle`): labels, errors, toasts, semantics labels, tooltips. No literal in a widget; brand names and server-sent user content excepted. Every key lands in every shipped locale in the same change; server error codes map to keys, never the server's message.
