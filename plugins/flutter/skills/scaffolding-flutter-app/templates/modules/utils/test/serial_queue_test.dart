import 'dart:async';

import 'package:test/test.dart';
import 'package:utils/utils.dart';

void main() {
  test('runs tasks one at a time, in order', () async {
    final queue = SerialQueue();
    final first = Completer<void>();
    final started = <int>[];

    final a = queue.add(() async {
      started.add(1);
      await first.future;
      return 1;
    });
    final b = queue.add(() async {
      started.add(2);
      return 2;
    });
    await Future<void>.delayed(Duration.zero);
    expect(started, [1]);

    first.complete();
    expect(await Future.wait([a, b]), [1, 2]);
    expect(started, [1, 2]);
  });

  test('a failed task fails only its own future', () async {
    final queue = SerialQueue();
    final failed = queue.add<int>(() => Future.error(StateError('boom')));
    final next = queue.add(() async => 2);

    await expectLater(failed, throwsStateError);
    expect(await next, 2);
  });
}
