import 'package:domain/domain_model.dart';
import 'package:test/test.dart';

void main() {
  // A tear-off builds non-const instances, so equality runs `props`.
  const foo = Foo.new;

  test('two foos with the same id are equal', () {
    expect(foo(id: 'foo-1'), foo(id: 'foo-1'));
    expect(foo(id: 'foo-1'), isNot(foo(id: 'foo-2')));
  });
}
