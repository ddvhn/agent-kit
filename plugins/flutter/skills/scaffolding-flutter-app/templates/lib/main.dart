import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:foo_app/bootstrap.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ui/ui.dart';

/// Mobile entry and composition root: with `bootstrap.dart`, the only code
/// that imports every layer.
Future<void> main() async {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized(); // live checks (driving-flutter-app)
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  final support = await getApplicationSupportDirectory();
  await bootstrap(
    app: const Application(),
    logsDirectoryPath: '${support.path}/logs',
  );
}
