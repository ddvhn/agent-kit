---
name: theming-flutter-apps
description: Theme a Flutter app the kit way — ThemeColors (a ThemeExtension of semantic color tokens named element-tone-variant, light and dark palettes), AppThemeX (a ThemeExtension holding one component theme per shared widget or screen with its text styles, decorations, button styles, and sizes, built by makeAppThemeX from the colors), theme.dart's makeTheme(platform:, brightness:) turning both into a ThemeData per platform and brightness with Material component themes, and palettes generated from a design-token file when the design has one; widgets read AppThemeX.of(context).fooPage and ThemeColors.of(context), never hardcoded colors or text styles. Use when creating the theme of a new app, adding a color token or a component theme, styling a new screen or shared widget, adding dark mode, or replacing hardcoded colors and text styles in widgets.
---

# Theming Flutter apps

Policy: the stack `dart` rule (widgets, accessibility: text scale, tap targets, contrast). Templates: `scaffolding-flutter-app` → `templates/modules/ui/lib/src/common/theme/`. The app's own design language: the project UI skill (below).

**Widgets never hardcode design values.** Colors come from `ThemeColors`, text styles and the look of a component from its entry in `AppThemeX`, stock Material widgets from `ThemeData`'s component themes. No `Color(0x…)`, `Colors.*`, or `TextStyle(…)` in a widget.

## Files

```
modules/ui/lib/src/common/theme/
  theme_colors.dart  # ThemeColors (ThemeExtension): lightColors, darkColors
  app_theme_x.dart   # AppThemeX (ThemeExtension): platform + one FooTheme per component / screen; makeAppThemeX(colors:, platform:)
  theme.dart         # makeTheme(platform:, brightness:): ThemeData + both extensions
  ui_platform.dart   # UiPlatform { ios, android, web }
  app_scroll_behavior.dart
modules/ui/lib/src/common/widgets/ # shared widgets, each styled by its AppThemeX entry
```

## Colors (`theme_colors.dart`)

Tokens are named `{element}{Tone}{Variant}`:

| Part | Values |
| --- | --- |
| element | `text`, `icon`, `border`, `surface`, plus `bg` (the page background) |
| tone | `Primary`, `Secondary`, `Neutral`, `Error` |
| variant | `Default`, `Weak`, `Light`, `Medium`, `Strong`, `Contrast` (on a filled surface), `Disabled` |

```dart
const lightColors = ThemeColors(
  textPrimaryDefault: Color(0xFF2F6F6B),
  textNeutralDefault: Color(0xFF282929),
  textNeutralMedium: Color(0xFF787A7A),
  textNeutralContrast: Color(0xFFFFFFFF),
  textErrorDefault: Color(0xFFC2252E),
  iconPrimaryDefault: Color(0xFF2F6F6B),
  borderNeutralWeak: Color(0xFFE9EAEA),
  bg: Color(0xFFFEFDFC),
  surfacePrimaryDefault: Color(0xFF2F6F6B),
  surfaceNeutralContrast: Color(0xFFFFFFFF),
  // … every token
);

const darkColors = ThemeColors(/* the same tokens, dark values */);

final class ThemeColors extends ThemeExtension<ThemeColors> {
  const ThemeColors({required this.textPrimaryDefault, /* … */});

  final Color textPrimaryDefault;
  // … one field per token

  final white = Colors.white;
  final black = Colors.black;

  static ThemeColors of(BuildContext context) =>
      Theme.of(context).extension<ThemeColors>() ??
      (throw StateError('ThemeColors is missing from ThemeData.extensions'));

  @override
  ThemeColors copyWith({Color? textPrimaryDefault /* , … */}) => ThemeColors(
    textPrimaryDefault: textPrimaryDefault ?? this.textPrimaryDefault,
    // …
  );

  /// Interpolates every token, so a light ↔ dark switch animates.
  @override
  ThemeColors lerp(ThemeExtension<ThemeColors>? other, double t) {
    if (other is! ThemeColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? b;
    return ThemeColors(
      textPrimaryDefault: mix(textPrimaryDefault, other.textPrimaryDefault),
      // …
    );
  }
}
```

- The token values are the design's; the palette is the only place a hex value appears.
- A new color is a new token in both palettes, `copyWith`, and `lerp`, named by the scheme above. A color used once in a widget is a missing token.
- `copyWith` and `lerp` are real (full template in the scaffolding skill), and `of` throws a clear error instead of `!`.
- **Dark mode**: a real `darkColors` palette. An app without a dark design ships `lightColors` only and sets `themeMode: ThemeMode.light` in `Application`; never alias `darkColors = lightColors`.

## Component themes (`app_theme_x.dart`)

Each shared widget and each screen with its own look gets an immutable component theme holding everything visual it needs, built from the colors in `makeAppThemeX`:

```dart
AppThemeX makeAppThemeX({
  required ThemeColors colors,
  required UiPlatform platform,
}) => AppThemeX(
  platform: platform,
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
    cardDecoration: BoxDecoration(
      color: colors.surfaceNeutralContrast,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: colors.borderNeutralWeak),
    ),
    contentPadding: const EdgeInsets.all(16),
    sectionGap: 24,
  ),
);

final class FooPageTheme {
  const FooPageTheme({
    required this.title,
    required this.cardDecoration,
    required this.contentPadding,
    required this.sectionGap,
  });

  final TextStyle title;
  final BoxDecoration cardDecoration;
  final EdgeInsets contentPadding;
  final double sectionGap;
}
```

`AppThemeX` itself is the extension that holds the entries:

```dart
final class AppThemeX extends ThemeExtension<AppThemeX> {
  const AppThemeX({required this.errorView, required this.fooPage});

  final ErrorViewTheme errorView;
  final FooPageTheme fooPage;

  static AppThemeX of(BuildContext context) =>
      Theme.of(context).extension<AppThemeX>() ??
      (throw StateError('AppThemeX is missing from ThemeData.extensions'));

  @override
  AppThemeX copyWith({ErrorViewTheme? errorView, FooPageTheme? fooPage}) =>
      AppThemeX(
        errorView: errorView ?? this.errorView,
        fooPage: fooPage ?? this.fooPage,
      );

  /// Component themes are rebuilt from ThemeColors per mode, so they switch
  /// halfway through a theme animation instead of interpolating.
  @override
  AppThemeX lerp(ThemeExtension<AppThemeX>? other, double t) =>
      other is AppThemeX && t >= 0.5 ? other : this;
}
```

- Fields are typed for what the widget sets: `TextStyle`, `Color`, `BoxDecoration`, `ButtonStyle`, `EdgeInsets`, `BorderRadius`, `double` (gaps, sizes), even `TextAlign` / alignment when the design fixes them. Names say the role in that component (`title`, `sectionTitle`, `cardDecoration`, `retryButton`).
- **Adding one**: the `final class FooPageTheme` at the end of `app_theme_x.dart`, a field on `AppThemeX` (constructor, `copyWith`), and its entry in `makeAppThemeX`. One entry per component, named after it (`fooPage`, `fooListItem`, `confirmationDialog`); a second screen with the same look reuses the entry rather than copying it.
- Text styles live only here. `theme.dart` sets only the base `TextTheme` colors (body and display text follow `textNeutralDefault`), so plain `Text` and stock widgets match the brightness; sizes and weights come from `AppThemeX` and the component themes.

## ThemeData (`theme.dart`)

One factory per platform and brightness (`ui` rule → Look and theme); `Application`, widget tests, and goldens all call it:

```dart
ThemeData makeTheme({
  required UiPlatform platform,
  required Brightness brightness,
}) => _makeTheme(
  colors: brightness == Brightness.dark ? darkColors : lightColors,
  brightness: brightness,
  platform: platform,
);

ThemeData _makeTheme({
  required ThemeColors colors,
  required Brightness brightness,
  required UiPlatform platform,
}) => ThemeData(
  brightness: brightness,
  platform: switch (platform) {
    UiPlatform.ios => TargetPlatform.iOS,
    // web pinned to Material: unset, `.adaptive` widgets follow the browser's OS
    UiPlatform.android || UiPlatform.web => TargetPlatform.android,
  },
  pageTransitionsTheme: /* Cupertino on iOS, predictive back on Android, none on web */,
  cupertinoOverrideTheme: CupertinoThemeData(
    brightness: brightness,
    primaryColor: colors.surfacePrimaryDefault,
    scaffoldBackgroundColor: colors.bg,
  ),
  visualDensity: VisualDensity.standard,
  colorScheme: ColorScheme.fromSeed(
    seedColor: colors.surfacePrimaryDefault,
    brightness: brightness,
  ).copyWith(surface: colors.bg, onSurface: colors.textNeutralDefault),
  textTheme: ThemeData(brightness: brightness).textTheme.apply(
    bodyColor: colors.textNeutralDefault,
    displayColor: colors.textNeutralDefault,
  ),
  extensions: [colors, makeAppThemeX(colors: colors, platform: platform)],
  scaffoldBackgroundColor: colors.bg,
  // appBar, buttons, snackBar, bottomSheet, inputDecoration, divider, card,
  // progressIndicator: the full set is in the template.
);
```

- `UiPlatform` is detected once in `injectUiLayer` and passed in; `AppThemeX.platform` carries it to `Adaptive*` widgets and the page helper (`building-adaptive-widgets`). The theme never reads `Platform` itself.
- Scroll physics per platform come from `AppScrollBehavior` on `MaterialApp.router(scrollBehavior:)`, not from each list.

- Every theme passes its `brightness` and a `ColorScheme` built from the tokens; without them a dark theme is a light scheme on a dark background (black text, purple defaults).
- Every stock widget the app uses (app bar, buttons, inputs, snackbars, sheets, dividers, cards, progress) is styled here once, so screens use `ElevatedButton` / `TextField` plain. A wrapper widget only when the design adds structure or behavior.
- `Application` passes `theme: makeTheme(platform: p, brightness: .light), darkTheme: makeTheme(platform: p, brightness: .dark)` (`scaffolding-flutter-app`).

## In widgets

```dart
@override
Widget build(BuildContext context) {
  final theme = AppThemeX.of(context).fooPage;
  return Container(
    decoration: theme.cardDecoration,
    padding: theme.contentPadding,
    child: Column(
      spacing: theme.sectionGap,
      children: [
        Text(foo.title, style: theme.title),
        Icon(Icons.check, color: ThemeColors.of(context).iconPrimaryDefault),
      ],
    ),
  );
}
```

- `final theme = AppThemeX.of(context).fooPage;` once at the top of `build`; plain colors with `ThemeColors.of(context).token`.
- Sizes that define the component's look (paddings, radii, gaps, icon sizes) come from its component theme; a one-off layout number inside one widget may stay a literal.
- Shared widgets in `common/widgets/` (`ErrorView`, loading indicator, empty view, confirmation dialog, list items) take content as parameters and their style from their own `AppThemeX` entry, never colors from the caller.
- Images and icons: decorative ones excluded from semantics; icon-only buttons carry a localized `tooltip` (stack `dart` rule).

## Accessibility

- Text scales with the system: no fixed heights around text, line `height` as a ratio, rows that wrap (stack `dart` rule). Check 2× in the running app (`driving-flutter-app`) or in a widget test with `MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(2)), …)`.
- Tap targets ≥ 48 × 48 in the button themes (`minimumSize: Size(48, 48)`); contrast of text tokens on their surfaces per the `dart` rule, in both palettes; state never conveyed by color alone.

## Tokens from a design file

When the design keeps tokens in a file (`docs/design/tokens.json`, the W3C design tokens format or the design tool's export), the palettes and the spacing, radius, type, and motion constants are **generated** from it, never edited by hand:

- `tool/generate_tokens.dart` reads the file and writes `modules/ui/lib/src/common/theme/generated/tokens.g.dart` (`lightColors`, `darkColors`, `Spacing`, `Radii`, `TypeScale`, `Motion`) and, for a web panel or emails, `tokens.css` with the same names as CSS custom properties.
- `scripts/test.sh unit` reruns it and fails when the output differs; the generated file is in the coverage exclusions.
- A missing value goes into the token file first, then regenerate. Values sit on a 4 px grid (`ui` rule → Look and theme).

## Web and admin apps

A web or admin app uses the same three files. It usually needs more shared entries (buttons, header bar, navigation bar, panels, list items) because screens repeat layouts; keep those as shared component themes rather than per-page copies.

## Project UI skill

The kit owns the mechanics; the app's design language goes to a skill in the repository's `.claude/skills/` (see `adopting-agent-kit`), for example `.claude/skills/<app>-design/SKILL.md`: the token table (token ↔ design-tool name ↔ use), the component catalogue (which shared widget and `AppThemeX` entry for which need), screen patterns (sheets vs pages, list density, motion), assets and icons, and the design source link. Agents read it before UI work.

## Procedure

1. Get the palette (light and dark) and map it to tokens by the naming scheme.
2. Fill `theme_colors.dart` (or generate it from the token file), the Material component themes in `theme.dart`, and the shared entries in `app_theme_x.dart`; wire `makeTheme` for light and dark in `Application`.
3. For a new screen or shared widget: add its component theme first, then the widget reading it.
4. Replace hardcoded values in widgets you touch (not a mass refactor).
5. Check light, dark, and 2× text on the main screens in the running app; update the project UI skill.

## Checks

- [ ] `grep -rnE "Color\(0x|(^|[^A-Za-z])Colors\.[a-z]|TextStyle\(" modules/ui/lib --include=*.dart | grep -v common/theme` shows nothing new (`Colors.transparent` aside)
- [ ] New colors are tokens in both palettes, `copyWith`, and `lerp`; no `darkColors = lightColors`
- [ ] Each new component or screen has its `AppThemeX` entry; widgets read it once per `build`
- [ ] Stock widgets styled through `ThemeData`; tap targets ≥ 48
- [ ] Light, dark (or explicit light-only), and 2× text checked
