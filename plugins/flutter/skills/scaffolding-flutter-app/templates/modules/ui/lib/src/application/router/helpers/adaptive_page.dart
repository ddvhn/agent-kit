import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui/src/common/theme/app_theme_x.dart';
import 'package:ui/src/common/theme/ui_platform.dart';

/// Every route builds its page here (ui rule → Navigation): native pushes
/// with swipe back on iOS, Material with predictive back on Android, and no
/// transition on web, where each screen is a real URL.
Page<T> adaptivePage<T>(
  BuildContext context,
  GoRouterState state,
  Widget child,
) => switch (AppThemeX.of(context).platform) {
  UiPlatform.ios => CupertinoPage<T>(
    key: state.pageKey,
    name: state.name,
    child: child,
  ),
  UiPlatform.android => MaterialPage<T>(
    key: state.pageKey,
    name: state.name,
    child: child,
  ),
  UiPlatform.web => NoTransitionPage<T>(
    key: state.pageKey,
    name: state.name,
    child: child,
  ),
};

/// A full-screen modal: slides up on iOS, a full-screen dialog on Android.
Page<T> adaptiveModalPage<T>(
  BuildContext context,
  GoRouterState state,
  Widget child,
) => switch (AppThemeX.of(context).platform) {
  UiPlatform.ios => CupertinoPage<T>(
    key: state.pageKey,
    name: state.name,
    fullscreenDialog: true,
    child: child,
  ),
  UiPlatform.android => MaterialPage<T>(
    key: state.pageKey,
    name: state.name,
    fullscreenDialog: true,
    child: child,
  ),
  UiPlatform.web => NoTransitionPage<T>(
    key: state.pageKey,
    name: state.name,
    child: child,
  ),
};

/// A sheet: the iOS page sheet with drag to dismiss on iOS, a modal bottom
/// sheet elsewhere.
Page<T> adaptiveSheetPage<T>(
  BuildContext context,
  GoRouterState state,
  Widget child,
) => _SheetPage<T>(
  key: state.pageKey,
  name: state.name,
  platform: AppThemeX.of(context).platform,
  child: child,
);

final class _SheetPage<T> extends Page<T> {
  const _SheetPage({
    required this.platform,
    required this.child,
    super.key,
    super.name,
  });

  final UiPlatform platform;
  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => switch (platform) {
    UiPlatform.ios => CupertinoSheetRoute<T>(
      settings: this,
      scrollableBuilder: (_, _) => child,
    ),
    UiPlatform.android || UiPlatform.web => ModalBottomSheetRoute<T>(
      settings: this,
      isScrollControlled: true,
      builder: (_) => child,
    ),
  };
}
