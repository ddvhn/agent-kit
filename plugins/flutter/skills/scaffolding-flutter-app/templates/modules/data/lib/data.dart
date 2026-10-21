// What the composition root needs: DI and config. Repositories, stores, and
// DTOs stay internal; test harnesses use `package:data/testing.dart`.
export 'package:data/src/config/app_config.dart';
export 'package:data/src/di.dart' show injectDataLayer;
