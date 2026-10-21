import 'package:flutter/material.dart';
import 'package:ui/src/common/theme/theme_colors.dart';
import 'package:ui/src/common/theme/ui_platform.dart';

/// One entry per shared component or screen: its text styles, decorations,
/// button styles, and the sizes that define its look, all derived from
/// [ThemeColors]. Widgets read `AppThemeX.of(context).fooPage`; adaptive
/// widgets and the page helper read `AppThemeX.of(context).platform`.
AppThemeX makeAppThemeX({
  required ThemeColors colors,
  required UiPlatform platform,
}) => AppThemeX(
  platform: platform,
  confirmationDialog: ConfirmationDialogTheme(
    title: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: colors.textNeutralDefault,
    ),
    content: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      color: colors.textNeutralStrong,
    ),
    defaultAction: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: colors.textPrimaryDefault,
    ),
    destructiveAction: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: colors.textErrorDefault,
    ),
  ),
  errorView: ErrorViewTheme(
    message: TextStyle(
      fontSize: 17,
      height: 1.4,
      fontWeight: FontWeight.w400,
      color: colors.textNeutralStrong,
    ),
    padding: const EdgeInsets.all(24),
    gap: 16,
  ),
  fooPage: FooPageTheme(
    title: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: colors.textNeutralDefault,
    ),
    description: TextStyle(
      fontSize: 15,
      height: 1.4,
      fontWeight: FontWeight.w400,
      color: colors.textNeutralStrong,
    ),
    cardDecoration: BoxDecoration(
      color: colors.surfaceNeutralContrast,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: colors.borderNeutralWeak),
    ),
    contentPadding: const EdgeInsets.all(16),
    sectionGap: 24,
  ),
);

final class AppThemeX extends ThemeExtension<AppThemeX> {
  const AppThemeX({
    required this.platform,
    required this.confirmationDialog,
    required this.errorView,
    required this.fooPage,
  });

  /// The look adaptive widgets follow; set once per app from the DI
  /// registration, and per test or golden by the theme it builds.
  final UiPlatform platform;
  final ConfirmationDialogTheme confirmationDialog;
  final ErrorViewTheme errorView;
  final FooPageTheme fooPage;

  static AppThemeX of(BuildContext context) =>
      Theme.of(context).extension<AppThemeX>() ??
      (throw StateError('AppThemeX is missing from ThemeData.extensions'));

  @override
  AppThemeX copyWith({
    UiPlatform? platform,
    ConfirmationDialogTheme? confirmationDialog,
    ErrorViewTheme? errorView,
    FooPageTheme? fooPage,
  }) => AppThemeX(
    platform: platform ?? this.platform,
    confirmationDialog: confirmationDialog ?? this.confirmationDialog,
    errorView: errorView ?? this.errorView,
    fooPage: fooPage ?? this.fooPage,
  );

  /// Component themes are rebuilt from [ThemeColors] per mode, so they switch
  /// halfway through a theme animation instead of interpolating.
  @override
  AppThemeX lerp(ThemeExtension<AppThemeX>? other, double t) =>
      other is AppThemeX && t >= 0.5 ? other : this;
}

final class ConfirmationDialogTheme {
  const ConfirmationDialogTheme({
    required this.title,
    required this.content,
    required this.defaultAction,
    required this.destructiveAction,
  });

  final TextStyle title;
  final TextStyle content;
  final TextStyle defaultAction;
  final TextStyle destructiveAction;
}

final class ErrorViewTheme {
  const ErrorViewTheme({
    required this.message,
    required this.padding,
    required this.gap,
  });

  final TextStyle message;
  final EdgeInsets padding;
  final double gap;
}

final class FooPageTheme {
  const FooPageTheme({
    required this.title,
    required this.description,
    required this.cardDecoration,
    required this.contentPadding,
    required this.sectionGap,
  });

  final TextStyle title;
  final TextStyle description;
  final BoxDecoration cardDecoration;
  final EdgeInsets contentPadding;
  final double sectionGap;
}
