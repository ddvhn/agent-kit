import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ui/src/application/router/helpers/adaptive_page.dart';
import 'package:ui/src/common/theme/theme.dart';
import 'package:ui/src/common/theme/ui_platform.dart';

/// Opens [location] on a router whose routes use the helpers, on [platform].
Future<void> _open(
  WidgetTester tester,
  UiPlatform platform,
  String location,
) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) =>
            adaptivePage(context, state, const Text('home')),
        routes: [
          GoRoute(
            path: 'modal',
            pageBuilder: (context, state) =>
                adaptiveModalPage(context, state, const Text('modal')),
          ),
          GoRoute(
            path: 'sheet',
            pageBuilder: (context, state) =>
                adaptiveSheetPage(context, state, const Text('sheet')),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: makeTheme(platform: platform, brightness: .light),
      routerConfig: router,
    ),
  );
  router.go(location);
  await tester.pumpAndSettle();
}

ModalRoute<Object?> _routeOf(WidgetTester tester, String text) =>
    ModalRoute.of<Object?>(tester.element(find.text(text)))!;

void main() {
  for (final (platform, page, sheet) in [
    (UiPlatform.ios, CupertinoPage, CupertinoSheetRoute),
    (UiPlatform.android, MaterialPage, ModalBottomSheetRoute),
    (UiPlatform.web, NoTransitionPage, ModalBottomSheetRoute),
  ]) {
    testWidgets('$platform pages', (tester) async {
      String typeName(Object object) => object.runtimeType.toString();

      await _open(tester, platform, '/');
      expect(
        typeName(_routeOf(tester, 'home').settings),
        startsWith(page.toString()),
      );

      await _open(tester, platform, '/modal');
      final modal = _routeOf(tester, 'modal');
      expect(typeName(modal.settings), startsWith(page.toString()));
      expect(
        modal,
        isA<PageRoute<Object?>>().having(
          (route) => route.fullscreenDialog,
          'fullscreenDialog',
          platform != UiPlatform.web,
        ),
      );

      await _open(tester, platform, '/sheet');
      expect(typeName(_routeOf(tester, 'sheet')), startsWith(sheet.toString()));
    });
  }
}
