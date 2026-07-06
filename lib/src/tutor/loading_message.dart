import 'package:flutter/material.dart';

/// A spinner with an explanatory line underneath, for waits long enough that
/// a bare spinner would look like the app has frozen (e.g. the one-time
/// corpus scan on first launch, or a fresh `GetNextStudyItem` round trip).
class LoadingMessage extends StatelessWidget {
  const LoadingMessage({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
