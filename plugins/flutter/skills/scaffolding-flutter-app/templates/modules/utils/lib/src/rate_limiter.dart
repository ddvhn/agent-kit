import 'dart:collection';

/// Allows at most [maxCalls] calls in any [window]; a call over the limit is
/// refused, not delayed (a support form, a resend button, a log burst).
/// Time is injected so tests step it.
final class RateLimiter {
  RateLimiter({
    required this.maxCalls,
    required this.window,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int maxCalls;
  final Duration window;
  final DateTime Function() _now;
  final _calls = Queue<DateTime>();

  /// Whether a call may go now; records it when it may.
  bool tryAcquire() {
    final now = _now();
    while (_calls.isNotEmpty && now.difference(_calls.first) >= window) {
      _calls.removeFirst();
    }
    if (_calls.length >= maxCalls) return false;
    _calls.addLast(now);
    return true;
  }
}
