import 'package:domain/domain_model.dart';
import 'package:flutter/material.dart';
import 'package:localization/localization.dart';
import 'package:ui/keys.dart';
import 'package:ui/src/common/extensions/app_exception_x.dart';
import 'package:ui/src/common/theme/app_theme_x.dart';

/// A failure with nothing else to show: the message and, when it can help,
/// a retry button. Scrollable, so it works inside a `RefreshIndicator`.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

  final AppException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeX.of(context).errorView;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: theme.padding,
      children: [
        Text(
          error.message(context.strings),
          style: theme.message,
          textAlign: TextAlign.center,
        ),
        if (error.isRetryable) ...[
          SizedBox(height: theme.gap),
          Center(
            child: ElevatedButton(
              key: keys.widgets.errorViewRetry,
              onPressed: onRetry,
              child: Text(context.strings.retry),
            ),
          ),
        ],
      ],
    );
  }
}
