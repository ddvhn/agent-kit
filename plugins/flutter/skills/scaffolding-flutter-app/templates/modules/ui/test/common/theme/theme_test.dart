import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/common/theme/app_scroll_behavior.dart';
import 'package:ui/src/common/theme/app_theme_x.dart';
import 'package:ui/src/common/theme/theme.dart';
import 'package:ui/src/common/theme/theme_colors.dart';
import 'package:ui/src/common/theme/ui_platform.dart';

void main() {
  group('UiPlatform', () {
    test('maps web, Apple, and everything else', () {
      expect(UiPlatform.detect(isWeb: true, isApple: true), UiPlatform.web);
      expect(UiPlatform.detect(isWeb: false, isApple: true), UiPlatform.ios);
      expect(
        UiPlatform.detect(isWeb: false, isApple: false),
        UiPlatform.android,
      );
    });

    test('current() answers for the host', () {
      expect(UiPlatform.values, contains(UiPlatform.current()));
    });
  });

  group('makeTheme', () {
    for (final platform in UiPlatform.values) {
      for (final brightness in Brightness.values) {
        test('$platform $brightness carries both extensions', () {
          final theme = makeTheme(platform: platform, brightness: brightness);

          expect(theme.brightness, brightness);
          expect(theme.extension<AppThemeX>()!.platform, platform);
          expect(theme.extension<ThemeColors>(), isNotNull);
          // Web is pinned to Material so `.adaptive` widgets stay Material.
          expect(
            theme.platform,
            platform == UiPlatform.ios
                ? TargetPlatform.iOS
                : TargetPlatform.android,
          );
        });
      }
    }

    test('page transitions follow the platform', () {
      PageTransitionsBuilder builderFor(UiPlatform platform) => makeTheme(
        platform: platform,
        brightness: .light,
      ).pageTransitionsTheme.builders[TargetPlatform.android]!;

      expect(builderFor(.ios), isA<CupertinoPageTransitionsBuilder>());
      expect(builderFor(.android), isA<PredictiveBackPageTransitionsBuilder>());
      expect(
        builderFor(.web),
        isNot(
          anyOf(
            isA<CupertinoPageTransitionsBuilder>(),
            isA<PredictiveBackPageTransitionsBuilder>(),
          ),
        ),
      );
    });

    testWidgets('web pushes without a transition', (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: makeTheme(platform: .web, brightness: .light),
          home: const SizedBox.shrink(),
        ),
      );

      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Text('next')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text('next'), findsOneWidget);
    });

    test('text buttons dim when disabled', () {
      final style = makeTheme(
        platform: .android,
        brightness: .light,
      ).textButtonTheme.style!;
      final enabled = style.foregroundColor!.resolve(<WidgetState>{});
      final disabled = style.foregroundColor!.resolve({WidgetState.disabled});

      expect(enabled, isNot(disabled));
    });
  });

  group('extensions', () {
    test('copyWith keeps every value; lerp switches or mixes', () {
      final light = makeTheme(platform: .ios, brightness: .light);
      final dark = makeTheme(platform: .ios, brightness: .dark);
      final lightX = light.extension<AppThemeX>()!;
      final darkX = dark.extension<AppThemeX>()!;
      final lightColors = light.extension<ThemeColors>()!;
      final darkColors = dark.extension<ThemeColors>()!;

      expect(lightX.copyWith().errorView, same(lightX.errorView));
      expect(lightX.lerp(darkX, 0.4), same(lightX));
      expect(lightX.lerp(darkX, 0.6), same(darkX));
      expect(lightX.lerp(null, 1), same(lightX));

      expect(
        lightColors.copyWith().textPrimaryDefault,
        lightColors.textPrimaryDefault,
      );
      expect(lightColors.lerp(darkColors, 0.5), isA<ThemeColors>());
      expect(lightColors.lerp(null, 1), same(lightColors));
    });

    testWidgets('of() fails clearly without the extension', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        Theme(
          data: ThemeData(),
          child: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(() => AppThemeX.of(context), throwsStateError);
      expect(() => ThemeColors.of(context), throwsStateError);
    });
  });

  group('AppScrollBehavior', () {
    testWidgets('bounces on iOS, clamps elsewhere, drags with a mouse on web', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      );

      expect(
        const AppScrollBehavior(.ios).getScrollPhysics(context),
        isA<BouncingScrollPhysics>(),
      );
      expect(
        const AppScrollBehavior(.android).getScrollPhysics(context),
        isA<ClampingScrollPhysics>(),
      );
      expect(
        const AppScrollBehavior(.web).dragDevices,
        contains(PointerDeviceKind.mouse),
      );
      expect(
        const AppScrollBehavior(.android).dragDevices,
        isNot(contains(PointerDeviceKind.mouse)),
      );
    });
  });
}
