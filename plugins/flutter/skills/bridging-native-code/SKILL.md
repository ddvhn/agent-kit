---
name: bridging-native-code
description: Call platform code from a Flutter app with pigeon — the API definition in the data package, generated Dart, Kotlin, and Swift committed and checked for freshness, the native implementation registered in the plugin or AppDelegate / MainActivity, a Dart adapter behind a data-layer contract, a web no-op or JS interop variant chosen by a factory, a fake for tests, and errors mapped to the data layer's exceptions. Use when a feature needs a native API no package offers (monotonic time with sleep, boot id, a Keystore / Secure Enclave key, backup exclusion, a system setting), or replacing a hand-written MethodChannel.
---

# Bridging native code

Policy: the `data` rule (platform services behind contracts, variants chosen by a factory) and the `architecture` rule → Platforms and assembly. Prefer a maintained package; write a bridge only when none fits, and never a hand-written `MethodChannel` with string method names.

**Ask first:** a new device permission or purpose string, and any native dependency (CocoaPods, Swift package, Gradle artifact).

## Layout

```
modules/data/pigeons/foo_device.dart                    # the pigeon definition (input)
modules/data/lib/src/generated/pigeon/foo_device.g.dart # generated Dart
ios/Runner/Pigeon/FooDevice.g.swift                     # generated Swift
android/app/src/main/kotlin/com/example/foo/pigeon/FooDevice.g.kt
ios/Runner/FooDeviceImpl.swift                          # hand-written host implementation
android/app/src/main/kotlin/com/example/foo/FooDeviceImpl.kt
modules/data/lib/src/device/
  foo_device_service.dart           # contract
  foo_device_service_native.dart    # adapter over the generated FooDeviceApi
  foo_device_service_web.dart       # web variant (no-op or JS interop)
```

When several apps need the bridge, it becomes a local plugin package (`modules/foo_device/`) with the same parts.

## Definition

```dart
// modules/data/pigeons/foo_device.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/generated/pigeon/foo_device.g.dart',
  swiftOut: '../../ios/Runner/Pigeon/FooDevice.g.swift',
  kotlinOut: '../../android/app/src/main/kotlin/com/example/foo/pigeon/FooDevice.g.kt',
  kotlinOptions: KotlinOptions(package: 'com.example.foo.pigeon'),
))
class MonotonicReading {
  MonotonicReading({required this.elapsedMillis, required this.bootId});
  int elapsedMillis;   // since boot, including sleep
  String bootId;
}

@HostApi()
abstract class FooDeviceApi {
  MonotonicReading readMonotonic();
  @async
  bool excludeFromBackup(String path);
}
```

Generate with `dart run pigeon --input pigeons/foo_device.dart` from `modules/data`, wrapped in `scripts/generate_pigeons.sh`; `scripts/test.sh unit` reruns it and fails on a diff. Generated files are excluded from analysis and coverage.

## Host side

- Android: `elapsedRealtime()` includes sleep; the boot id from `/proc/sys/kernel/random/boot_id` (or `Settings.Global.BOOT_COUNT`). Register with `FooDeviceApi.setUp(flutterEngine.dartExecutor.binaryMessenger, FooDeviceImpl(context))` in `MainActivity.configureFlutterEngine`.
- iOS: monotonic time including sleep is `clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)` (`mach_continuous_time`; `CLOCK_MONOTONIC` also counts sleep); `CLOCK_UPTIME_RAW` (`mach_absolute_time`) stops while the device sleeps, so never use it here. The boot id is `sysctl kern.bootsessionuuid` (a new UUID every boot; `kern.boottime` moves when the clock is set, so it is not an id). Register in `AppDelegate.didInitializeImplicitFlutterEngine` (or `application(_:didFinishLaunchingWithOptions:)`).
- Throw `FlutterError(code:message:details:)` / `PigeonError` with stable codes; never crash the app.
- Keep host code thin: no business rules, only the platform call and its error codes.

## Dart side

```dart
abstract interface class FooDeviceService {
  Future<MonotonicTime> readMonotonic();
  Future<void> excludeFromBackup(String path);
}

final class FooDeviceServiceNative implements FooDeviceService {
  FooDeviceServiceNative([FooDeviceApi? api]) : _api = api ?? FooDeviceApi();
  final FooDeviceApi _api;

  @override
  Future<MonotonicTime> readMonotonic() async {
    try {
      final reading = await _api.readMonotonic();
      return MonotonicTime(elapsed: Duration(milliseconds: reading.elapsedMillis), bootId: reading.bootId);
    } on PlatformException catch (e) {
      throw DeviceServiceException(code: e.code);
    }
  }

  @override
  Future<void> excludeFromBackup(String path) => _api.excludeFromBackup(path);
}
```

- The factory in `injectDataLayer` picks the variant with `UniversalPlatform.isWeb` (`di` rule → Wiring); nothing else checks the platform.
- Web: a no-op where the concept does not exist (backup exclusion) or `dart:js_interop` / `package:web` where it does; the same contract.

## Tests

- The adapter with a mocked generated `FooDeviceApi` (`mocktail`): mapping and each error code. The generated class and host code are excluded from coverage; the adapter is not.
- Screens and use cases use a `FakeFooDeviceService` (steppable monotonic time, a settable boot id), also in the Patrol harness.
- Host code: a small XCTest / JUnit test when it has logic beyond the call; otherwise the device smoke covers it.
