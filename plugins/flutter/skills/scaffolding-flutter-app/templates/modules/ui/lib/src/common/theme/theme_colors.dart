import 'package:flutter/material.dart';

/// Color tokens named `{element}{Tone}{Variant}`: element `text`, `icon`,
/// `border`, `surface` (plus `bg`); tone `Primary`, `Secondary`, `Neutral`,
/// `Error`; variant `Default`, `Weak`, `Light`, `Medium`, `Strong`,
/// `Contrast`, `Disabled`. Values come from the design; these are examples.
const lightColors = ThemeColors(
  textPrimaryDefault: Color(0xFF2F6F6B),
  textNeutralDefault: Color(0xFF282929),
  textNeutralMedium: Color(0xFF787A7A),
  textNeutralStrong: Color(0xFF505151),
  textNeutralContrast: Color(0xFFFFFFFF),
  textErrorDefault: Color(0xFFC2252E),

  iconPrimaryDefault: Color(0xFF2F6F6B),
  iconNeutralLight: Color(0xFFA0A2A2),
  iconNeutralDisabled: Color(0xFFDFDFDF),

  borderPrimaryDefault: Color(0xFF2F6F6B),
  borderNeutralWeak: Color(0xFFE9EAEA),

  bg: Color(0xFFFEFDFC),

  surfacePrimaryDefault: Color(0xFF2F6F6B),
  surfacePrimaryWeak: Color(0xFFCFEBE9),
  surfaceNeutralContrast: Color(0xFFFFFFFF),
  surfaceNeutralLight: Color(0xFFE9EAEA),
);

const darkColors = ThemeColors(
  textPrimaryDefault: Color(0xFF6FC2BC),
  textNeutralDefault: Color(0xFFF2F2F2),
  textNeutralMedium: Color(0xFFA0A2A2),
  textNeutralStrong: Color(0xFFD0D1D1),
  textNeutralContrast: Color(0xFF00201E),
  textErrorDefault: Color(0xFFFF6B6B),

  iconPrimaryDefault: Color(0xFF6FC2BC),
  iconNeutralLight: Color(0xFF787A7A),
  iconNeutralDisabled: Color(0xFF3A3B3B),

  borderPrimaryDefault: Color(0xFF6FC2BC),
  borderNeutralWeak: Color(0xFF38393A),

  bg: Color(0xFF121212),

  surfacePrimaryDefault: Color(0xFF6FC2BC),
  surfacePrimaryWeak: Color(0xFF1F3B39),
  surfaceNeutralContrast: Color(0xFF1E1F1F),
  surfaceNeutralLight: Color(0xFF2A2B2B),
);

final class ThemeColors extends ThemeExtension<ThemeColors> {
  const ThemeColors({
    required this.textPrimaryDefault,
    required this.textNeutralDefault,
    required this.textNeutralMedium,
    required this.textNeutralStrong,
    required this.textNeutralContrast,
    required this.textErrorDefault,
    required this.iconPrimaryDefault,
    required this.iconNeutralLight,
    required this.iconNeutralDisabled,
    required this.borderPrimaryDefault,
    required this.borderNeutralWeak,
    required this.bg,
    required this.surfacePrimaryDefault,
    required this.surfacePrimaryWeak,
    required this.surfaceNeutralContrast,
    required this.surfaceNeutralLight,
  });

  final Color textPrimaryDefault;
  final Color textNeutralDefault;
  final Color textNeutralMedium;
  final Color textNeutralStrong;
  final Color textNeutralContrast;
  final Color textErrorDefault;
  final Color iconPrimaryDefault;
  final Color iconNeutralLight;
  final Color iconNeutralDisabled;
  final Color borderPrimaryDefault;
  final Color borderNeutralWeak;
  final Color bg;
  final Color surfacePrimaryDefault;
  final Color surfacePrimaryWeak;
  final Color surfaceNeutralContrast;
  final Color surfaceNeutralLight;

  final white = Colors.white;
  final black = Colors.black;

  static ThemeColors of(BuildContext context) =>
      Theme.of(context).extension<ThemeColors>() ??
      (throw StateError('ThemeColors is missing from ThemeData.extensions'));

  @override
  ThemeColors copyWith({
    Color? textPrimaryDefault,
    Color? textNeutralDefault,
    Color? textNeutralMedium,
    Color? textNeutralStrong,
    Color? textNeutralContrast,
    Color? textErrorDefault,
    Color? iconPrimaryDefault,
    Color? iconNeutralLight,
    Color? iconNeutralDisabled,
    Color? borderPrimaryDefault,
    Color? borderNeutralWeak,
    Color? bg,
    Color? surfacePrimaryDefault,
    Color? surfacePrimaryWeak,
    Color? surfaceNeutralContrast,
    Color? surfaceNeutralLight,
  }) => ThemeColors(
    textPrimaryDefault: textPrimaryDefault ?? this.textPrimaryDefault,
    textNeutralDefault: textNeutralDefault ?? this.textNeutralDefault,
    textNeutralMedium: textNeutralMedium ?? this.textNeutralMedium,
    textNeutralStrong: textNeutralStrong ?? this.textNeutralStrong,
    textNeutralContrast: textNeutralContrast ?? this.textNeutralContrast,
    textErrorDefault: textErrorDefault ?? this.textErrorDefault,
    iconPrimaryDefault: iconPrimaryDefault ?? this.iconPrimaryDefault,
    iconNeutralLight: iconNeutralLight ?? this.iconNeutralLight,
    iconNeutralDisabled: iconNeutralDisabled ?? this.iconNeutralDisabled,
    borderPrimaryDefault: borderPrimaryDefault ?? this.borderPrimaryDefault,
    borderNeutralWeak: borderNeutralWeak ?? this.borderNeutralWeak,
    bg: bg ?? this.bg,
    surfacePrimaryDefault: surfacePrimaryDefault ?? this.surfacePrimaryDefault,
    surfacePrimaryWeak: surfacePrimaryWeak ?? this.surfacePrimaryWeak,
    surfaceNeutralContrast:
        surfaceNeutralContrast ?? this.surfaceNeutralContrast,
    surfaceNeutralLight: surfaceNeutralLight ?? this.surfaceNeutralLight,
  );

  /// Interpolates every token, so a light ↔ dark switch animates.
  @override
  ThemeColors lerp(ThemeExtension<ThemeColors>? other, double t) {
    if (other is! ThemeColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? b;
    return ThemeColors(
      textPrimaryDefault: mix(textPrimaryDefault, other.textPrimaryDefault),
      textNeutralDefault: mix(textNeutralDefault, other.textNeutralDefault),
      textNeutralMedium: mix(textNeutralMedium, other.textNeutralMedium),
      textNeutralStrong: mix(textNeutralStrong, other.textNeutralStrong),
      textNeutralContrast: mix(textNeutralContrast, other.textNeutralContrast),
      textErrorDefault: mix(textErrorDefault, other.textErrorDefault),
      iconPrimaryDefault: mix(iconPrimaryDefault, other.iconPrimaryDefault),
      iconNeutralLight: mix(iconNeutralLight, other.iconNeutralLight),
      iconNeutralDisabled: mix(iconNeutralDisabled, other.iconNeutralDisabled),
      borderPrimaryDefault: mix(
        borderPrimaryDefault,
        other.borderPrimaryDefault,
      ),
      borderNeutralWeak: mix(borderNeutralWeak, other.borderNeutralWeak),
      bg: mix(bg, other.bg),
      surfacePrimaryDefault: mix(
        surfacePrimaryDefault,
        other.surfacePrimaryDefault,
      ),
      surfacePrimaryWeak: mix(surfacePrimaryWeak, other.surfacePrimaryWeak),
      surfaceNeutralContrast: mix(
        surfaceNeutralContrast,
        other.surfaceNeutralContrast,
      ),
      surfaceNeutralLight: mix(surfaceNeutralLight, other.surfaceNeutralLight),
    );
  }
}
