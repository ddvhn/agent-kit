import 'package:data/src/core/disposable.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Resource implements Disposable {
  var disposed = false;

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  test('disposes a Disposable', () async {
    final resource = _Resource();
    await disposeIfDisposable(resource);
    expect(resource.disposed, isTrue);
  });

  test('ignores anything else', () async {
    await expectLater(disposeIfDisposable(Object()), completes);
  });
}
