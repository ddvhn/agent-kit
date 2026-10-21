import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:ui/src/common/theme/app_theme_x.dart';
import 'package:ui/src/common/theme/ui_platform.dart';

/// The activity indicator for short actions only: inside a pressed button,
/// while sending (ui rule → Widgets). The iOS indicator on iOS,
/// the Material one elsewhere. The pattern for every `Adaptive*` widget
/// (building-adaptive-widgets).
class AdaptiveSpinner extends StatelessWidget {
  const AdaptiveSpinner({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: switch (AppThemeX.of(context).platform) {
      UiPlatform.ios => CupertinoActivityIndicator(radius: size / 2),
      UiPlatform.android ||
      UiPlatform.web => const CircularProgressIndicator(strokeWidth: 2),
    },
  );
}
