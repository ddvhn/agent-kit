---
name: configuring-flutter-flavors
description: Add, rename, or change Flutter build flavors and build-time configuration end to end — Android productFlavors, iOS schemes, build configurations and xcconfigs, per-flavor Firebase config files, app name and icon, appFlavor and dart-defines in Dart, launch configs, Patrol and CI build commands, and verification. Use when setting up flavors (for example staging / prod), adding a flavor or a dart-define, changing a bundle id, app name, icon, or Firebase app per flavor, or gating a production service (analytics, ads, purchases, backend).
---

# Configuring Flutter flavors

Policy: the stack `di` rule → Build configuration. The project's flavor names, bundle ids, Firebase projects, launch configs, and defines: `CLAUDE.md` → Project facts and the repository's `.claude/rules/`. Follow the existing setup's file locations; the kit's default set is `dev`, `staging`, `prod` (the same three on every target); examples below show `staging` and `prod` with bundle ids `com.example.foo.staging` / `com.example.foo`, and `dev` follows the `staging` pattern (`com.example.foo.dev`). `dev` is what developers, agents, Patrol, and the mock app run.

**Ask first:** changing a shipped bundle id / applicationId (a new store app), the prod Firebase app or project, signing, or which flavor Patrol and QA install.

## Decide before editing

| Belongs to | What |
| --- | --- |
| Flavor (native, compile time) | bundle id / applicationId, home-screen name, icon, Firebase app config (`google-services.json`, `GoogleService-Info.plist`), entitlements, URL schemes that come from the Firebase app |
| Dart-define | backend or emulator host and ports, switches that turn on production services, fake or mock toggles |
| Entry point (`-t lib/main_mock.dart`) | a mock or demo build on the non-prod flavor — not a third flavor unless it must install side by side |
| Not flavored | version (`pubspec.yaml`), Android `namespace`, signing (unless the project says so), web |

Production services need the prod flavor **and** an explicit define (`PROD_SERVICES=true`): the `di` rule → Build configuration.

## What `--flavor staging` does

1. **Android:** builds the Gradle variant `stagingDebug` / `stagingRelease` (flavor × build type) with that flavor's `applicationId`, placeholders, and `src/staging/` source set.
2. **iOS:** builds the Xcode scheme named exactly `staging` with configuration `Debug-staging` / `Release-staging` / `Profile-staging`.
3. **Dart:** sets `appFlavor` (`package:flutter/services.dart`) to `'staging'`; `null` on web, in `flutter test`, and without `--flavor`.

Once flavors exist, mobile `flutter run` / `build` / `patrol test` without `--flavor` fail. Flavor and define changes need a full rebuild.

## Android

`android/app/build.gradle.kts` (Groovy: `flavorDimensions "env"`, `staging { … }`, `manifestPlaceholders = [appName: "…"]`):

```kotlin
android {
    flavorDimensions += "env"
    productFlavors {
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".staging"
            manifestPlaceholders["appName"] = "Foo Staging"
        }
        create("prod") {
            dimension = "env"
            manifestPlaceholders["appName"] = "Foo"
        }
    }
}
```

- `AndroidManifest.xml`: `android:label="${appName}"`; authorities built from `${applicationId}` (FileProvider), never hardcoded.
- Icons and flavor resources: `android/app/src/<flavor>/res/`. `namespace` stays as is (it is the Kotlin / `R` package, not the install id).
- Firebase: `android/app/src/<flavor>/google-services.json` per flavor, or one multi-client file in `android/app/` (the Google Services plugin picks the client by `applicationId`). Keep the project's choice; each applicationId must be registered as a Firebase Android app.

## iOS

1. **Configurations** (Xcode → Runner project → Info): duplicate `Debug`, `Release`, `Profile` into `Debug-staging`, `Release-staging`, `Profile-staging`, and the same for `prod`. Name format `<Mode>-<flavor>` is what Flutter expects.
2. **xcconfigs** in `ios/Flutter/`, set as each configuration's base configuration on the Runner target:

   ```
   // Flavor-staging.xcconfig — no quotes around values
   PRODUCT_BUNDLE_IDENTIFIER = com.example.foo.staging
   APP_DISPLAY_NAME = Foo Staging
   ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon-staging

   // Debug-staging.xcconfig
   #include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.debug-staging.xcconfig"
   #include "Generated.xcconfig"
   #include "Flavor-staging.xcconfig"
   ```

   Release and Profile files include the `release-<flavor>` / `profile-<flavor>` Pods file. Without CocoaPods (Swift Package Manager only), drop the Pods include. Remove hardcoded `PRODUCT_BUNDLE_IDENTIFIER` and app icon from the target's build settings — they override the xcconfig.
3. **Info.plist:** `CFBundleIdentifier` = `$(PRODUCT_BUNDLE_IDENTIFIER)`, `CFBundleDisplayName` = `$(APP_DISPLAY_NAME)`. Values that differ per Firebase app (Google Sign-In `REVERSED_CLIENT_ID` URL scheme) and per-flavor entitlements (`CODE_SIGN_ENTITLEMENTS`, associated domains) also go through the xcconfig.
4. **Podfile** (CocoaPods only): map the new configurations, then `pod install`:

   ```ruby
   project 'Runner', {
     'Debug-staging' => :debug, 'Profile-staging' => :release, 'Release-staging' => :release,
     'Debug-prod' => :debug, 'Profile-prod' => :release, 'Release-prod' => :release,
   }
   ```
5. **Schemes:** Product → Scheme → Manage Schemes → duplicate `Runner` as `staging` and `prod`, tick **Shared** (files land in `xcshareddata/xcschemes/` and are committed). Run / Test / Analyze → `Debug-<flavor>`, Profile → `Profile-<flavor>`, Archive → `Release-<flavor>`. Keep the scheme's build pre-actions. Keep `Runner` building the non-prod app.
6. **GoogleService-Info.plist:** one file per flavor (`ios/Runner/Firebase/<flavor>/GoogleService-Info.plist` or the project's folder), **not** in Copy Bundle Resources. A Run Script phase after Copy Bundle Resources installs the right one; the default branch is non-prod:

   ```bash
   set -euo pipefail
   case "${CONFIGURATION}" in
     *-prod) SRC="${PROJECT_DIR}/Runner/Firebase/prod/GoogleService-Info.plist" ;;
     *)      SRC="${PROJECT_DIR}/Runner/Firebase/staging/GoogleService-Info.plist" ;;
   esac
   cp "${SRC}" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/GoogleService-Info.plist"
   ```

   List both plists as the phase's input files when user script sandboxing is on. A Crashlytics symbol-upload phase must pick the plist the same way.

## Firebase in Dart

- Mobile: `Firebase.initializeApp()` without `options` reads the native file the flavor installed. Prefer this.
- If the project uses FlutterFire's generated options: one file per flavor (`flutterfire configure --project=<id> --out=lib/firebase_options_<flavor>.dart --ios-bundle-id=… --android-package-name=…`), chosen by `appFlavor`. One options file for all flavors pins every flavor to one Firebase app. `flutterfire configure` also rewrites native config files: review its diff.
- Web has no `--flavor`: its Firebase options come from its own entry point or defines.

## appFlavor and dart-defines

`AppConfig` lives in `modules/data/lib/src/config/app_config.dart`, the one config object of the app. The scaffold has only `environment` (`appFlavor` on mobile, the `ENVIRONMENT` define on web, `dev` when neither is set); add a field there for each switch, when its feature arrives:

```dart
factory AppConfig.fromEnvironment() => const AppConfig(
  environment: _environment,
  apiBaseUrl: String.fromEnvironment('API_BASE_URL'),
  useProdServices:
      _environment == 'prod' && bool.fromEnvironment('PROD_SERVICES'),
  useCrashlytics: bool.fromEnvironment('CRASHLYTICS'),
  useEmulators: _environment != 'prod' && bool.fromEnvironment('USE_EMULATORS'),
  emulatorHost: String.fromEnvironment(
    'EMULATOR_HOST',
    defaultValue: 'localhost',
  ),
);
```

| Define | Field | Set by |
| --- | --- | --- |
| `PROD_SERVICES=true` | `useProdServices` (analytics, ads, purchases) | prod release config and prod CI builds |
| `CRASHLYTICS=true` | `useCrashlytics` (collection on, handlers forward) | release configs and CI builds of every flavor |
| `USE_EMULATORS=true` | `useEmulators` (never on prod) | `dev-local` |
| `EMULATOR_HOST` | `emulatorHost` (default `localhost`) | `.dart_defines.local.json` (git-ignored; a device's LAN IP, `10.0.2.2` for an Android emulator) |

- Read flavor and defines once at startup (`main`), pass the config through DI; widgets and repositories never call `fromEnvironment` or read `appFlavor`.
- `bool.fromEnvironment` / `String.fromEnvironment` only as `const`.
- Switches go on the command line (`--dart-define=CRASHLYTICS=true`); machine-specific values go in `.dart_defines.local.json` (`--dart-define-from-file`, git-ignored, with a committed `.example`). Defines ship in the binary: never secrets.
- Choose implementations in DI from the config (`di` rule → Wiring), not with `if`s across the code.

## Web environments

Flutter has no native flavors on web, so the web target gets the same environments as config files, one per environment, committed (no secrets — they ship in the bundle):

```json
// config/web/staging.json
{
  "ENVIRONMENT": "staging",
  "API_BASE_URL": "https://api.staging.example.com",
  "CRASHLYTICS": "true"
}
```

```bash
flutter run -d chrome -t lib/main_web.dart --dart-define-from-file=config/web/dev.json
flutter build web --release -t lib/main_web.dart --dart-define-from-file=config/web/prod.json
```

Only `config/web/prod.json` sets `"PROD_SERVICES": "true"`, the web counterpart of the prod release define; `useProdServices` still needs `ENVIRONMENT` to be `prod` as well.

`AppConfig.fromEnvironment()` reads the same keys on both targets; mobile builds pass their per-environment values with `--dart-define-from-file=config/mobile/<env>.json` next to `--flavor <env>` when they need more than the flavor. A web build without a config file runs as `dev`, never `prod`.

## Launch configs, Patrol, CI

`.vscode/launch.json` (or the IDE the project uses), one entry per flavor × mode the team runs:

```json
{
  "name": "dev-agent",
  "type": "dart",
  "request": "launch",
  "program": "lib/main.dart",
  "flutterMode": "debug",
  "args": ["--flavor", "dev"],
  "toolArgs": ["--host-vmservice-port=8181", "--disable-service-auth-codes"]
}
```

The scaffold's configs: `dev-debug` (the team's default, VM-service auth codes on), `dev-agent` (above: the fixed VM-service port without auth codes, so the Dart and Marionette MCP servers can attach — `driving-flutter-app`; only on a trusted machine, debug and non-prod only), `dev-local` (a local backend: `USE_EMULATORS=true` or a local `API_BASE_URL` from `--dart-define-from-file=.dart_defines.local.json`, git-ignored with a committed `.example`), `mock` (`test/main_mock.dart`, no backend — `mocking-backend-for-tests`), `release-staging`, and `web-dev` when the app has a web entry. No launch config runs against the production backend; a prod build is made by the release lanes (`releasing-flutter-apps`). Features add their defines: `CRASHLYTICS=true` on the release configs with crash reporting, `PROD_SERVICES=true` on prod.

- Patrol builds and installs `dev` (`patrol test --flavor dev`; `setting-up-patrol`).
- Store builds: every command names the flavor and its defines (`flutter build appbundle --release --flavor prod --dart-define=PROD_SERVICES=true`). The release lanes read flavor, bundle id, package, and defines from one `APPS` table per flavor (`releasing-flutter-apps`); a new flavor adds its entry there in the same change.

## Firebase and crash reporting

The scaffold has no Firebase. The first Firebase feature (a backend — `calling-cloud-functions`, sign-in — `adding-flutter-auth`, crash reporting) adds `firebase_core` to the app and data, a Firebase app per flavor with its config files (above), and the SDK step in `bootstrap.dart` after the config:

```dart
await Firebase.initializeApp(); // mobile: the flavor's native config; web: its options
final crashlytics = config.useCrashlytics && !UniversalPlatform.isWeb;
if (!UniversalPlatform.isWeb) {
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(crashlytics);
}
_installErrorHandlers(crashlytics: crashlytics);
```

The error handlers keep logging and also forward when `crashlytics` is on: `FirebaseCrashlytics.instance.recordFlutterError(details)` (non-fatal framework errors; `recordFlutterFatalError` only for the ones the app treats as crashes) instead of `FlutterError.presentError`, and `recordError(error, stackTrace, fatal: true)` for `PlatformDispatcher.onError`. Crashlytics receives uncaught errors only (`handling-errors`). `firebase_crashlytics` goes in the app's pubspec.

Patrol always installs the `dev` flavor: its `patrol:` block (`flavor`, `test_directory`, package name, bundle id) is in `setting-up-patrol` → 2.

Builds (CI and local) go through `flutter build`, which passes flavor and defines:

```bash
flutter build appbundle --release --flavor prod --dart-define=PROD_SERVICES=true --dart-define=CRASHLYTICS=true
flutter build ipa --release --flavor prod --dart-define=PROD_SERVICES=true --dart-define=CRASHLYTICS=true --export-options-plist=ios/ExportOptions.plist
flutter build apk --debug --flavor staging
```

Xcode Archive and raw Gradle tasks do not pass dart-defines unless configured; a prod binary built that way silently gets the non-prod defaults. Outputs are per variant (`build/app/outputs/bundle/prodRelease/`). Update CI jobs, store upload ids, and README / `CLAUDE.md` → Verification commands to the new names.

Icons: `flutter_launcher_icons-<flavor>.yaml` per flavor (the suffix is the flavor; it writes `src/<flavor>/res` and `AppIcon-<flavor>.appiconset`), then `dart run flutter_launcher_icons`. No unsuffixed config next to them.

## Verify

- [ ] `flutter run --flavor <each>` starts on Android and iOS; name and icon differ; both flavors install side by side
- [ ] Identity of the built app: `plutil -p build/ios/iphoneos/Runner.app/Info.plist | grep -E 'CFBundle(Identifier|DisplayName)'`; Android `adb shell pm list packages | grep <applicationId>`
- [ ] Firebase app per flavor: `plutil -p <Runner.app>/GoogleService-Info.plist | grep BUNDLE_ID`; in a debug run, `Firebase.app().options.projectId` / `appId` match the flavor
- [ ] Release builds of each flavor succeed (`flutter build appbundle` / `flutter build ios --no-codesign`)
- [ ] `flutter test` (no flavor) passes and resolves to non-prod; Patrol runs on the non-prod flavor
- [ ] `grep -rnE 'kReleaseMode|kDebugMode'` finds no production-service gate
- [ ] Launch configs, CI, and documented commands all pass `--flavor`

## Pitfalls

- Flavor name differs between Gradle, the Xcode scheme, and `--flavor` → native build error, not a Dart error.
- Quoted values in an xcconfig become part of the bundle id.
- Two `GoogleService-Info.plist` files in Copy Bundle Resources → an arbitrary one ships.
- Target-level build settings silently override the xcconfig.
- Hot reload after changing a flavor or define changes nothing.
- A mock entry point on the non-prod flavor replaces the installed non-prod app (same bundle id).
