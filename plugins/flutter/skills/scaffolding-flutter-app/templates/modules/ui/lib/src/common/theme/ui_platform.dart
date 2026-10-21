import 'package:universal_platform/universal_platform.dart';

/// The platform look a screen follows (ui rule → Look and theme). Detected
/// once, by [UiPlatform.current] in `injectUiLayer`; widgets read it from the
/// theme (`AppThemeX.of(context).platform`), so widget tests and goldens pick
/// a platform by the theme they build.
enum UiPlatform {
  ios,
  android,
  web;

  /// The running platform. Desktop follows its closest mobile look.
  static UiPlatform current() => detect(
    isWeb: UniversalPlatform.isWeb,
    isApple: UniversalPlatform.isIOS || UniversalPlatform.isMacOS,
  );

  /// The mapping, pure so tests cover every case on any host.
  static UiPlatform detect({required bool isWeb, required bool isApple}) =>
      isWeb ? web : (isApple ? ios : android);
}
