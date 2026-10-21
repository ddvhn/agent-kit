import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/common/theme/ui_platform.dart';
import 'package:ui/src/common/widgets/adaptive/adaptive_spinner.dart';

import '../../../helpers/pump_screen.dart';

void main() {
  for (final (platform, type) in [
    (UiPlatform.ios, CupertinoActivityIndicator),
    (UiPlatform.android, CircularProgressIndicator),
    (UiPlatform.web, CircularProgressIndicator),
  ]) {
    testWidgets('$platform shows $type', (tester) async {
      await pumpScreen(tester, const AdaptiveSpinner(), platform: platform);

      expect(find.byType(type), findsOneWidget);
    });
  }
}
