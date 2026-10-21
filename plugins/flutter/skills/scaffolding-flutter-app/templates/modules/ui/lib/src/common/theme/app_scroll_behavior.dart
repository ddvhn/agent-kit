import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:ui/src/common/theme/ui_platform.dart';

/// Scrolling per platform: bouncing on iOS, clamping on Android, and on web
/// clamping with mouse drag and the default scrollbars.
final class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior(this.platform);

  final UiPlatform platform;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => switch (platform) {
    UiPlatform.ios => const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    ),
    UiPlatform.android || UiPlatform.web => const ClampingScrollPhysics(),
  };

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    if (platform == UiPlatform.web) PointerDeviceKind.mouse,
  };
}
