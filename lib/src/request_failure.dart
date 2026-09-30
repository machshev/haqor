import 'dart:async';

import 'package:flutter/material.dart';

import 'bindings/bindings.dart';

/// The `RequestFailed.request` names Rust answers with, one per request a
/// page waits on.
const String requestStudyState = 'study_state';
const String requestVerseText = 'verse_text';
const String requestNextStudyItem = 'next_study_item';
const String requestSubmitReview = 'submit_review';
const String requestSubmitMisreads = 'submit_misreads';
const String requestSeenConcepts = 'seen_concepts';
const String requestTutorStats = 'tutor_stats';
const String requestTutorSettings = 'tutor_settings';
const String requestSetTutorSettings = 'set_tutor_settings';
const String requestOnboardingStatus = 'onboarding_status';
const String requestCalibrationProbe = 'calibration_probe';
const String requestMemoryPassages = 'memory_passages';
const String requestMemoryLayout = 'memory_layout';
const String requestMemoryItem = 'memory_item';
const String requestMemoryRecital = 'memory_recital';
const String requestMemoryStats = 'memory_stats';

/// How long a page waits for Rust before it stops spinning and offers a retry.
/// Rust answers every request, even a failed one, so this only bounds a
/// request it never got to (a handler that panicked while serving it).
const Duration requestTimeout = Duration(seconds: 20);

/// Listen for Rust failing [request] (for [key], where a page can have several
/// of the request in flight, such as a verse as `book:chapter:verse`).
StreamSubscription<RequestFailed> listenForFailure(
  String request,
  void Function(RequestFailed failure) onFailed, {
  String? key,
}) => RequestFailed.rustSignalStream
    .map((pack) => pack.message)
    .where((m) => m.request == request && (key == null || m.key == key))
    .listen(onFailed);

/// A timer for one outstanding request: [start] it when the request goes out,
/// [stop] it when the reply (or a failure) arrives.
class RequestTimer {
  Timer? _timer;

  void start(VoidCallback onTimeout, {Duration timeout = requestTimeout}) {
    _timer?.cancel();
    _timer = Timer(timeout, onTimeout);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// What a page shows where a reply never came: the reason and a way to ask
/// again.
class RequestErrorView extends StatelessWidget {
  const RequestErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
