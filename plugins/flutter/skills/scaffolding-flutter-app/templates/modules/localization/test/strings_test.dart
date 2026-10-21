import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';

void main() {
  testWidgets('context.strings reads the current locale', (tester) async {
    late AppLocalizations strings;
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('en'),
        delegates: AppLocalizations.localizationsDelegates,
        child: Builder(
          builder: (context) {
            strings = context.strings;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(strings.localeName, 'en');
  });
}
