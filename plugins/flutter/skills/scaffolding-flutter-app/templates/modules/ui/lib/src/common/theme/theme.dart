import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:ui/src/common/theme/app_theme_x.dart';
import 'package:ui/src/common/theme/theme_colors.dart';
import 'package:ui/src/common/theme/ui_platform.dart';

/// The one theme factory (ui rule → Look and theme): a `ThemeData` per
/// platform and brightness, built only from tokens. `Application`, widget
/// tests, and goldens all call it.
ThemeData makeTheme({
  required UiPlatform platform,
  required Brightness brightness,
}) => _makeTheme(
  colors: brightness == Brightness.dark ? darkColors : lightColors,
  brightness: brightness,
  platform: platform,
);

/// Material component themes from [ThemeColors], so stock widgets match the
/// design without wrappers; app-specific styles live in [AppThemeX]. The color
/// scheme and base text colors come from the same tokens, so widgets without a
/// component theme (dialogs, switches, plain `Text`) follow the brightness.
/// The platform sets transitions, the Cupertino look, and density.
ThemeData _makeTheme({
  required ThemeColors colors,
  required Brightness brightness,
  required UiPlatform platform,
}) => ThemeData(
  brightness: brightness,
  // Web is pinned to the Material look: left unset, `.adaptive` widgets
  // would follow the browser's OS and render Cupertino on Apple machines.
  platform: switch (platform) {
    UiPlatform.ios => TargetPlatform.iOS,
    UiPlatform.android || UiPlatform.web => TargetPlatform.android,
  },
  pageTransitionsTheme: PageTransitionsTheme(
    builders: {
      for (final target in TargetPlatform.values)
        target: switch (platform) {
          UiPlatform.ios => const CupertinoPageTransitionsBuilder(),
          UiPlatform.android => const PredictiveBackPageTransitionsBuilder(),
          UiPlatform.web => const _NoTransitionsBuilder(),
        },
    },
  ),
  cupertinoOverrideTheme: CupertinoThemeData(
    brightness: brightness,
    primaryColor: colors.surfacePrimaryDefault,
    scaffoldBackgroundColor: colors.bg,
    barBackgroundColor: colors.bg,
  ),
  visualDensity: VisualDensity.standard,
  colorScheme:
      ColorScheme.fromSeed(
        seedColor: colors.surfacePrimaryDefault,
        brightness: brightness,
      ).copyWith(
        primary: colors.surfacePrimaryDefault,
        onPrimary: colors.textNeutralContrast,
        primaryContainer: colors.surfacePrimaryWeak,
        surface: colors.bg,
        onSurface: colors.textNeutralDefault,
        onSurfaceVariant: colors.textNeutralMedium,
        surfaceContainerHighest: colors.surfaceNeutralLight,
        outline: colors.borderPrimaryDefault,
        outlineVariant: colors.borderNeutralWeak,
        error: colors.textErrorDefault,
        onError: colors.textNeutralContrast,
      ),
  textTheme: ThemeData(brightness: brightness).textTheme.apply(
    bodyColor: colors.textNeutralDefault,
    displayColor: colors.textNeutralDefault,
  ),
  extensions: [
    colors,
    makeAppThemeX(colors: colors, platform: platform),
  ],
  scaffoldBackgroundColor: colors.bg,
  appBarTheme: AppBarTheme(
    backgroundColor: colors.bg,
    centerTitle: false,
    scrolledUnderElevation: 0,
    titleTextStyle: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: colors.textNeutralDefault,
    ),
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: colors.textErrorDefault,
    contentTextStyle: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: colors.textNeutralContrast,
    ),
  ),
  bottomSheetTheme: BottomSheetThemeData(backgroundColor: colors.bg),
  inputDecorationTheme: InputDecorationTheme(
    enabledBorder: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      borderSide: BorderSide(color: colors.borderNeutralWeak),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      borderSide: BorderSide(width: 2, color: colors.borderPrimaryDefault),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      borderSide: BorderSide(color: colors.textErrorDefault),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      borderSide: BorderSide(width: 2, color: colors.textErrorDefault),
    ),
    contentPadding: const EdgeInsets.all(12),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      foregroundColor: colors.textNeutralContrast,
      backgroundColor: colors.surfacePrimaryDefault,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      minimumSize: const Size(48, 48),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? colors.textNeutralMedium
            : colors.textPrimaryDefault,
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
    ),
  ),
  dividerTheme: DividerThemeData(color: colors.borderNeutralWeak, thickness: 1),
  cardTheme: CardThemeData(
    clipBehavior: Clip.hardEdge,
    color: colors.surfaceNeutralContrast,
  ),
  progressIndicatorTheme: ProgressIndicatorThemeData(
    color: colors.iconPrimaryDefault,
  ),
);

/// Web pages change at once (ui rule → Navigation).
final class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
