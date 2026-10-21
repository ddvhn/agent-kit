import 'package:test/test.dart';
import 'package:utils/utils.dart';

void main() {
  late DateTime now;
  late RateLimiter limiter;

  setUp(() {
    now = DateTime.utc(2030);
    limiter = RateLimiter(
      maxCalls: 2,
      window: const Duration(seconds: 10),
      now: () => now,
    );
  });

  test('refuses the call over the limit inside the window', () {
    expect([limiter.tryAcquire(), limiter.tryAcquire()], [true, true]);
    expect(limiter.tryAcquire(), isFalse);
  });

  test('allows again exactly when the oldest call leaves the window', () {
    limiter
      ..tryAcquire()
      ..tryAcquire();
    now = now.add(const Duration(seconds: 9, milliseconds: 999));
    expect(limiter.tryAcquire(), isFalse);
    now = now.add(const Duration(milliseconds: 1));
    expect(limiter.tryAcquire(), isTrue);
  });
}
