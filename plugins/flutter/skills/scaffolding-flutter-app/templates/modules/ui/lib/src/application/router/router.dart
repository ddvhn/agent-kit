import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:localization/localization.dart';
import 'package:ui/src/application/router/helpers/adaptive_page.dart';
import 'package:ui/src/home/pages/home_page.dart';

part 'router.g.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Registered once in `injectUiLayer` (adding-flutter-routes). Every route
/// builds its page with the adaptive helpers. An auth gate adds a `redirect`
/// here (adding-flutter-auth).
GoRouter createRouter() => GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: const HomeRoute().location,
  routes: $appRoutes,
  errorBuilder: (context, state) => const _NotFoundPage(),
);

@TypedGoRoute<HomeRoute>(path: '/', name: 'Home')
@immutable
class HomeRoute extends GoRouteData with $HomeRoute {
  const HomeRoute();

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      adaptivePage(context, state, const HomePage());
}

class _NotFoundPage extends StatelessWidget {
  const _NotFoundPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: Center(child: Text(context.strings.pageNotFound)),
  );
}
