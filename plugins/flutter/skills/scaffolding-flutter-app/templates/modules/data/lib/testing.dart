// Data internals for test harnesses only (test/, patrol_test/,
// integration_test/). tool/check_layers.dart fails if any lib/ imports this
// file. Add exports as harnesses need them: store contracts to replace, the
// real database for per-test instances, DTOs to seed.
export 'package:data/src/core/disposable.dart';
