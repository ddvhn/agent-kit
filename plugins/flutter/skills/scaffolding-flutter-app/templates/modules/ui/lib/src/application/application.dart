import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:localization/localization.dart';
import 'package:ui/src/common/theme/app_scroll_behavior.dart';
import 'package:ui/src/common/theme/theme.dart';
import 'package:ui/src/common/theme/ui_platform.dart';
import 'package:ui/src/di.dart';

/// The app shell: the one `MaterialApp.router` on every platform (ui rule →
/// Look and theme). App-wide blocs (a session, for example —
/// adding-flutter-auth) are created once here, in a `MultiBlocProvider` above
/// the router, so every route and the router's redirect read the same
/// instances.
class Application extends StatefulWidget {
  const Application({super.key});

  @override
  State<Application> createState() => _ApplicationState();
}

class _ApplicationState extends State<Application> {
  final _router = inject<GoRouter>();
  final _platform = inject<UiPlatform>();

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: _router,
    theme: makeTheme(platform: _platform, brightness: .light),
    darkTheme: makeTheme(platform: _platform, brightness: .dark),
    scrollBehavior: AppScrollBehavior(_platform),
    onGenerateTitle: (context) => context.strings.appTitle,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
  );
}
