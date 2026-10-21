import 'package:flutter/widgets.dart';
import 'package:localization/generated/app_localizations.dart';

export 'package:localization/generated/app_localizations.dart';

extension StringsX on BuildContext {
  /// The app's copy: `context.strings.fooTitle`.
  AppLocalizations get strings => AppLocalizations.of(this);
}
