import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:foo_app/bootstrap.dart';
import 'package:ui/ui.dart';

/// Web entry (architecture rule → Platforms and assembly), only when the
/// project ships a web app. The same layers; the inject functions pick the
/// web implementations. Real URLs without `#`, so browser back, deep links,
/// and reloads work (ui rule → Navigation).
///
/// flutter run -d chrome -t lib/main_web.dart \
///   --dart-define-from-file=config/web/dev.json
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  // A web app with its own screens passes its own shell here.
  await bootstrap(app: const Application());
}
