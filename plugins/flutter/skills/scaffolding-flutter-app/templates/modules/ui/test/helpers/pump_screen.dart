import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:ui/src/common/theme/theme.dart';
import 'package:ui/src/common/theme/ui_platform.dart';

/// Pumps [screen] the way the app shows it: the real theme for [platform]
/// and [brightness], the real copy in [locale], a text scale, and a screen
/// size (writing-widget-tests). Blocs come from the container, registered by
/// the test over fake use cases.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  UiPlatform platform = UiPlatform.android,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
  double textScale = 1,
  Size size = const Size(390, 844),
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: makeTheme(platform: platform, brightness: brightness),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: screen,
    ),
  );
}
