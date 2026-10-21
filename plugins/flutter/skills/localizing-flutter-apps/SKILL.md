---
name: localizing-flutter-apps
description: Add or change user-visible copy in a Flutter app with gen-l10n in one shared localization package used by the mobile and web entries (ARB files, AppLocalizations, context.strings) — every static string through it, key naming, locales kept in sync, plurals and placeholders, server error codes mapped to keys, formatting with intl, regeneration and its freshness check. Use when adding copy, changing copy, or adding a locale.
---

# Localization (gen-l10n)

The project's ARB directory, template file, locale list, generated output, and the `BuildContext` accessor for strings: the repository's `.claude/rules/` (and `l10n.yaml`). Content localized by the backend (entity titles, descriptions, translated media) is not ARB copy; it comes from the API — see the repository rules if the app has such a client.

## Setup (new app)

The copy lives in its own package, `modules/localization` (templates: `scaffolding-flutter-app`):

```yaml
# modules/localization/l10n.yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-dir: lib/generated
output-localization-file: app_localizations.dart
nullable-getter: false
```

```dart
// modules/localization/lib/localization.dart
import 'package:flutter/widgets.dart';
import 'package:localization/generated/app_localizations.dart';

export 'package:localization/generated/app_localizations.dart';

extension StringsX on BuildContext {
  /// The app's copy: `context.strings.fooTitle`.
  AppLocalizations get strings => AppLocalizations.of(this);
}
```

- The package's pubspec has `flutter_localizations`, `intl`, and `flutter: generate: true`; `ui` depends on it; `Application` passes `AppLocalizations.localizationsDelegates` / `supportedLocales`.
- The seed `lib/l10n/app_en.arb` holds the keys the kit's templates use: `appTitle`, `signIn`, `retry`, `pageNotFound`, and the error copy of `handling-errors` (`errorOffline`, `errorNotFound`, `errorSignedOut`, `errorNotAllowed`, `errorTooManyRequests`, `errorInvalidInput`, `errorGeneric`).
- Generate with `flutter gen-l10n` in `modules/localization`; `lib/generated/` is excluded from analysis. Add a locale by adding `app_<locale>.arb` with every key.
- Copy in tests: `lookupAppLocalizations(const Locale('en'))` gives the same strings without a widget tree.

## Adding a key

1. Key = camelCase of the **English** source copy (ignore ALL CAPS and
   punctuation). Drop articles (`a` / `an` / `the`) only when the
   phrase is long. Parameterized: suffix `Template` and ICU
   placeholders (`"durationWithHoursTemplate": "{hours}h {minutes}m"`).
   Name the string, not the screen or feature. Same copy → one key,
   reused. `Save` → `save`. `Please wait...` → `pleaseWait`.
   The project's existing key convention wins if it differs.
2. Copy change that would make the key a lie → **new key**. Delete the
   old key if unused.
3. Add the key to **every** locale's ARB file (locales stay in sync;
   the template locale is the source of truth). Translate when the
   project expects translations; otherwise follow what neighbors do.
4. Plurals: ICU (`"daysCount": "{days, plural, =1{1 day} other{{days} days}}"`).
5. No `@` metadata blocks unless neighbors for that key already have them.
6. Never hardcode user-visible copy in widgets; read it through
   `context.strings` (or the project's accessor). That covers titles,
   labels, buttons, hints, empty states, errors, toasts, dialogs,
   semantics labels, tooltips, and web tables and filters (`ui` rule →
   Copy). Brand names and server-sent user content are the only
   literals.
7. Regenerate (`flutter gen-l10n` in the package that owns `l10n.yaml`,
   or the project's command) — never edit generated files.

## Notes

- Server error codes map to keys in one place (the error presenter of
  `handling-errors`); never show the server's `message`.
- A new locale lands with every key; the stress golden of each screen
  runs in the longest locale (`writing-widget-tests` → Goldens).
- `scripts/test.sh unit` reruns `flutter gen-l10n` and fails when the
  generated files differ from the committed ones.

- Do not put backend-owned content (entity names, descriptions) into ARB.
- Dates, numbers, and currencies: format with `intl` using the current
  locale, not string concatenation.
