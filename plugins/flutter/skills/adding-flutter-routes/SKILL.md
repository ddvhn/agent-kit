---
name: adding-flutter-routes
description: Add or change screens, path and query parameters, tabs, modals, redirects, and navigation calls in a Flutter app that uses go_router with typed routes (go_router_builder). Use when adding a screen or route, passing parameters to a page, returning a result from a page, adding a tab or a modal, or changing the auth redirect.
---

# Adding Flutter routes (typed go_router)

Policy: the stack `ui` rule → Navigation. This skill is for apps on `go_router` + `go_router_builder`. An app on plain `Navigator` or string-path `GoRouter` keeps its style unless the user asks to migrate. The router file, root navigator key, page helpers (sheets, transitions), and redirect source: the repository's `.claude/rules/` or the existing router.

## Setup (once per app)

- `go_router` in the UI package; `go_router_builder` and `build_runner` as dev dependencies.
- One router file with `part 'router.g.dart';`. The generated `$appRoutes` list goes into `GoRouter(routes: $appRoutes, …)`.
- A private root navigator key (`final _rootNavigatorKey = GlobalKey<NavigatorState>();`) passed as `navigatorKey:` and reused by modal routes.
- `MaterialApp.router(routerConfig: router)` on every platform (`ui` rule → Look and theme); create the router once (not in `build`).
- On web, `usePathUrlStrategy()` in `main_web.dart` so URLs have no `#`.

## Add a screen

1. Define the route next to the others in the router file:

   ```dart
   @TypedGoRoute<FooDetailsRoute>(path: '/foo/:fooId', name: 'FooDetails')
   @immutable
   class FooDetailsRoute extends GoRouteData with $FooDetailsRoute {
     const FooDetailsRoute({required this.fooId, this.source});

     final String fooId; // path parameter: :fooId
     final String? source; // query parameter: ?source=

     @override
     Page<void> buildPage(BuildContext context, GoRouterState state) =>
         adaptivePage(context, state, FooDetailsPage(fooId: fooId));
   }
   ```

   - Path: lowercase kebab case, ids as `:segments`. `name:` in PascalCase, unique — screen analytics and logs use it.
   - Parameters: a field named like a `:segment` is a required path parameter; every other field is a query parameter and must be nullable or have a default. Supported types: `String`, `int`, `double`, `num`, `bool`, `DateTime`, `Uri`, `BigInt`, enums, and iterables of these for query parameters.
   - Pass ids and small values, not entities: the page creates its bloc and loads by id. Avoid `$extra` — it does not survive deep links, web refresh, or state restoration.
   - Every route overrides `buildPage(context, state)` and returns a page from the adaptive page helper (below) instead of `build`; no route builds its own `Page`.
   - Use primary constructors (`class const FooRoute(...)`) only if the project's SDK and neighbors already do.
2. Run the generator in the UI package: `dart run build_runner build` (command: `CLAUDE.md` → Verification).
3. Navigate with the route class from the widget's handler:

   ```dart
   FooDetailsRoute(fooId: foo.id).push(context); // on top of the stack
   const HomeRoute().go(context); // replace the stack (switch tab / flow)
   ```

   `go` for top-level destinations and flow switches, `push` for drill-down and modals — the way neighboring screens of the same flow do (shell, tab, modal, nested route). Never `context.go('/foo/$id')`. Compare locations with `const FooRoute().location`, not string literals.

## Adaptive page helper

`ui/lib/src/application/router/helpers/adaptive_page.dart` (template: `scaffolding-flutter-app`) builds every page from the platform in `AppThemeX`:

| Helper | iOS | Android | Web |
| --- | --- | --- | --- |
| `adaptivePage` (push) | `CupertinoPage`: parallax, edge swipe back | `MaterialPage`: the theme's transition, predictive back | `NoTransitionPage` |
| `adaptiveModalPage` (full-screen modal) | `CupertinoPage(fullscreenDialog: true)`: slides up | `MaterialPage(fullscreenDialog: true)` | `NoTransitionPage` |
| `adaptiveSheetPage` (sheet) | `CupertinoSheetRoute`: page sheet, drag to dismiss | `ModalBottomSheetRoute` | `ModalBottomSheetRoute` |

- Tab branches use `NoTransitionPage` on every platform.
- A new presentation style (a side panel on wide web screens) is a new helper here, with its widget test per platform.
- Test: build each helper with a `GoRouterState` stub and `pumpScreen(platform: …)`, and expect the page or route type (`building-adaptive-widgets` → Tests).


## Navigation policy

- **Fully typed `go_router`** (`go_router_builder`) in new apps: every screen, sheet, and full-screen modal is a route class with typed parameters; navigate only through route classes (`FooRoute(fooId: id).push(context)`), never string paths or `$extra`; one global `redirect` for gates. An app on another style keeps it unless asked to migrate.
- **One adaptive page helper** in `ui/lib/src/application/router/helpers/` builds every route's page; no route builds its own `Page`:
  - iOS: `CupertinoPage` pushes (parallax and edge swipe back), full-screen modals sliding up, page sheets with drag to dismiss;
  - Android: `MaterialPage` with the platform's current transition and predictive back, full-screen dialogs, modal bottom sheets;
  - web: `NoTransitionPage`; every screen has a real URL, browser back and forward and deep links work, and a reload restores the screen from its URL;
  - tab switches (`StatefulShellRoute`) have no transition on any platform.
- A widget test per helper checks the page type each platform gets. Details: `adding-flutter-routes`.

## Results from a page

```dart
final picked = await const PickBarRoute().push<Bar>(context);
if (!context.mounted || picked == null) return;
```

The page returns with `context.pop(bar)`. Refresh data after a modal closes the same way (`await …push(context)`, check `mounted`, then call the owning bloc).

## Tabs (stateful shell)

```dart
@TypedStatefulShellRoute<TabsRoute>(
  branches: [
    TypedStatefulShellBranch<StatefulShellBranchData>(
      routes: [TypedGoRoute<HomeRoute>(path: '/home', name: 'Home')],
    ),
    TypedStatefulShellBranch<StatefulShellBranchData>(
      routes: [TypedGoRoute<SettingsRoute>(path: '/settings', name: 'Settings')],
    ),
  ],
)
@immutable
class TabsRoute extends StatefulShellRouteData {
  const TabsRoute();

  @override
  Widget builder(
    BuildContext context,
    GoRouterState state,
    StatefulNavigationShell navigationShell,
  ) => TabsPage(navigationShell: navigationShell);
}
```

- Tab child routes (`HomeRoute`, `SettingsRoute`) are plain `GoRouteData` classes without their own annotation; their routes are declared in the branch.
- Tab pages use `NoTransitionPage` (override `buildPage` in the tab's route). Switch tabs with `navigationShell.goBranch(index)` or `const SettingsRoute().go(context)`.
- A custom branch container (keeping tab state, animations): `static Widget $navigatorContainerBuilder(context, navigationShell, children)` on the shell route.

## Modals above the tabs

```dart
@TypedGoRoute<FooPickerRoute>(path: '/foo-picker', name: 'FooPicker')
@immutable
class FooPickerRoute extends GoRouteData with $FooPickerRoute {
  const FooPickerRoute();

  static final GlobalKey<NavigatorState> $parentNavigatorKey =
      _rootNavigatorKey;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      adaptiveSheetPage(context, state, const FooPickerPage());
}
```

A top-level route with `$parentNavigatorKey` = the root key covers the shell (tab bar hidden). Without it, a route nested in a branch opens inside that tab.

## Redirect and auth

- The session bloc (`ObserveSessionBloc`) is app-wide: `Application` creates it once in its `MultiBlocProvider` above the router (`blocs` rule). The router template: `scaffolding-flutter-app`; the session, the redirect, and `SignInRoute`: `adding-flutter-auth`.
- One global `redirect` on the `GoRouter`. Read the session bloc state (`context.read<ObserveSessionBloc>().state`) and `switch` over its sealed states exhaustively; return a route `.location` or `null`. Do not redirect to the current location (loop). Signed out, a deep link goes to `SignInRoute(from: state.uri.toString())`; after sign-in the redirect returns to `from` when it is an in-app path (never another origin), else Home. On web the data layer waits for the restored user before the first frame, so a signed-in user is never bounced through sign-in.
- Refresh the router when the session changes: a `BlocListener` on `ObserveSessionBloc` in `Application` calling `router.refresh()`.
- Per-route guards only through the same redirect (add the location to its rules); never check auth inside a page to bounce the user.

## Checks

- [ ] Route class, `name:`, and path follow neighbors; generator re-run
- [ ] Path parameters required, query parameters nullable or defaulted; ids passed, not objects
- [ ] All navigation through route classes; no string paths
- [ ] Page built by the adaptive page helper; web URL reload restores the screen
- [ ] Modal vs in-tab decided (`$parentNavigatorKey`)
- [ ] Redirect still exhaustive; no loop; new public routes allowed for signed-out users where needed; a signed-out deep link returns to its page after sign-in
- [ ] Integration test (`writing-patrol-tests`) for a new flow: open the screen through the UI, assert the page and its parameters
