import 'package:domain/domain_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/foo/models/foo_ui_model.dart';

void main() {
  // A tear-off builds non-const instances, so equality runs `props`.
  const model = FooUiModel.new;

  test('maps the id and compares by value', () {
    expect(FooUiModel.fromFoo(const Foo(id: 'foo-1')), model(id: 'foo-1'));
    expect(model(id: 'foo-1'), isNot(model(id: 'foo-2')));
  });
}
