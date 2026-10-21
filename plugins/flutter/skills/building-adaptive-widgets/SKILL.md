---
name: building-adaptive-widgets
description: Make a Flutter screen or widget look native on iOS, Android, and web from one MaterialApp.router — the per-platform ThemeData factory (makeTheme with UiPlatform and brightness), UiPlatform detected once at assembly and carried by AppThemeX, thin Adaptive* umbrella widgets (button, switch, dialog, sheet, spinner, refresh, navigation bar, date picker) that switch on the theme's platform, web hover, cursors, focus, and keyboard, the adaptive page helper, and widget and golden tests per platform. Use when a component must differ between Cupertino and Material, adding an Adaptive* widget, adding web hover or focus, or fixing a screen that branches on Platform.isIOS / kIsWeb.
---

# Building adaptive widgets

Policy: the `ui` rule → Look and theme, Widgets; platform detection: the `architecture` rule → Platforms and assembly. Templates: `scaffolding-flutter-app` → `templates/modules/ui/lib/src/common/theme/` (`ui_platform.dart`, `theme.dart`, `app_scroll_behavior.dart`) and `common/widgets/adaptive/adaptive_spinner.dart`. Theme values: `theming-flutter-apps`.


## Platform look

- Apple Human Interface Guidelines quality on every screen: hierarchy, navigation, sheets, alerts, lists, controls, and gestures behave the way users of the platform expect; the same structure maps to Material on Android. Invent nothing: standard platform components and patterns first. A custom component exists only when no standard one fits, and it is added to the project UI skill before it spreads.
- Everything sits on a 4 px grid: spacing, radii, and sizes come from tokens; the same element has the same padding on every screen. No one-off values.
- iOS gets Cupertino page transitions, edge swipe back, sheets, alerts and action sheets, switches, pickers, bouncing scroll, and the activity indicator; Android gets Material transitions, predictive back, dialogs, bottom sheets, `RefreshIndicator`, and the circular indicator; web gets no page transitions, mouse cursors and hover states on everything clickable, visible focus, and keyboard navigation. Brand look (colors, type, radii) is the same everywhere.
- Accessibility thresholds: the `dart` rule (this rule does not repeat them).

- Widgets that already adapt are used directly: `Switch.adaptive`, `CircularProgressIndicator.adaptive`, `showAdaptiveDialog`, `Slider.adaptive`, `Checkbox.adaptive`.
- Where components really differ, screens use one thin umbrella widget from `ui/lib/src/common/widgets/adaptive/` (`AdaptiveButton`, `AdaptiveSwitch`, `AdaptiveDialog`, `AdaptiveSheet`, `AdaptiveSpinner`, `AdaptiveNavigationBar`, `AdaptiveDatePicker`, `AdaptiveRefresh`, `AdaptiveScrollPhysics`). Each picks the Cupertino or Material implementation from the platform the theme carries (`AppThemeX.of(context).platform`) and styles it from the theme, so tests and goldens choose the platform by theme. Screens never branch on the platform themselves.
- No `flutter_platform_widgets` or similar package. A new `Adaptive*` widget only when a standard widget cannot adapt; it gets a widget test and a golden per platform.

## How the platform reaches a widget

1. `injectUiLayer` registers `UiPlatform.current()` once (`UniversalPlatform` inside; macOS maps to `ios`, Windows and Linux to `android` unless the project ships desktop; the mapping itself is the pure `UiPlatform.detect`, tested on any host).
2. `Application` builds `makeTheme(platform:, brightness:)` for light and dark; the factory puts `platform` into `AppThemeX`.
3. A widget reads `AppThemeX.of(context).platform`. Nothing else reads `Platform`, `defaultTargetPlatform`, `kIsWeb`, or `UniversalPlatform`.

Tests and goldens pick the platform by building the theme for it (`pumpScreen(platform: UiPlatform.ios)`), with no global overrides.

## Pick the lightest tool

| Need | Use |
| --- | --- |
| Same widget, platform default is fine | `Switch.adaptive`, `Slider.adaptive`, `Checkbox.adaptive`, `CircularProgressIndicator.adaptive`, `showAdaptiveDialog` + `AlertDialog.adaptive` — they follow `ThemeData.platform`, which `makeTheme` pins to Material on web |
| Same widget, different look | the component theme in `makeTheme` (padding, radius, ripple vs highlight) |
| Different component | one `Adaptive*` widget in `common/widgets/adaptive/` |
| Different screen structure | a different layout chosen by size (`flutter-build-responsive-layout`), not by platform |

## Adaptive* pattern

```dart
class AdaptiveSwitch extends StatelessWidget {
  const AdaptiveSwitch({required this.value, required this.onChanged, super.key});

  final bool value;
  final ValueChanged<bool>? onChanged; // null = disabled

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeX.of(context);
    return switch (theme.platform) {
      UiPlatform.ios => CupertinoSwitch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: theme.adaptiveSwitch.activeTrackColor,
      ),
      UiPlatform.android || UiPlatform.web => Switch(
        value: value,
        onChanged: onChanged,
      ),
    };
  }
}
```

- The public API is the smallest common one (value, callback, label); no platform-specific parameters leak to screens.
- Styling comes from its `AppThemeX` entry (`theme.adaptiveSwitch`), never from tokens or `Colors.*`.
- `switch` over `UiPlatform` is exhaustive with no `default`, so a new platform fails compilation.
- Dialogs and sheets are functions next to the widget (`showAdaptiveSheet(context, builder:)`) that return the result; the route-backed versions are the page helper's `adaptiveSheetPage` / `adaptiveModalPage` (`adding-flutter-routes`).
- Buttons: `AdaptiveButton` with `filled`, `tinted`, `plain` variants (Cupertino) mapped to `FilledButton`, `FilledButton.tonal`, `TextButton` (Material); a `loading` flag shows `AdaptiveSpinner` inside and ignores taps.
- Pull-to-refresh: `AdaptiveRefresh` (`CupertinoSliverRefreshControl` on iOS, `RefreshIndicator` elsewhere) with one `Future<void> Function()` callback.

## Web

- Every clickable widget shows a pointer cursor (`MouseRegion(cursor: SystemMouseCursors.click)` or the button's `mouseCursor`) and a hover state from its theme entry.
- Visible focus for keyboard users (`FocusableActionDetector`, focus colors in the theme); `Tab` order follows the reading order; `Enter` / `Space` activate.
- No page transitions; `AppScrollBehavior` adds mouse drag and scrollbars.
- Text selectable where users expect to copy (ids, addresses): `SelectionArea` around the content.

## Tests

- A widget test per `Adaptive*` widget and platform: the right implementation (`find.byType(CupertinoSwitch)` for `ios`), disabled when the callback is null, the callback fires once per tap, semantics label present.
- A golden per platform for each `Adaptive*` widget (`goldens/adaptive_switch_ios.png`, `_android`, `_web`) — `writing-widget-tests` → Goldens.
- A widget test for the page helper: `adaptivePage` returns `CupertinoPage` / `MaterialPage` / `NoTransitionPage` per platform; `adaptiveSheetPage` creates `CupertinoSheetRoute` / `ModalBottomSheetRoute`.
- Web hover: `TestGesture` with `PointerDeviceKind.mouse`, `addPointer`, `moveTo` the widget, then expect the hover decoration and `SystemMouseCursors.click` (`RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)`).

## Fixing a screen that branches on the platform

1. Find the branches: `grep -rnE "Platform\.is|kIsWeb|defaultTargetPlatform|UniversalPlatform" modules/ui/lib`.
2. Each one becomes a theme value, an existing adaptive constructor, or an `Adaptive*` widget (table above).
3. Write the per-platform widget tests first, then replace the branch; only assembly code keeps `UniversalPlatform`.
