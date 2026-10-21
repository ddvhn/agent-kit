import 'package:domain/domain_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/foo/blocs/load_foo_bloc.dart';
import 'package:ui/src/foo/models/foo_ui_model.dart';

/// States compare by value, so the bloc skips an equal emit and builders
/// skip an equal rebuild. Tear-offs build non-const instances, so equality
/// runs `props`.
void main() {
  const foo = FooUiModel(id: 'foo-1');
  const other = FooUiModel(id: 'foo-2');
  const error = NetworkUnavailableException();
  const idle = LoadFooBlocStateIdle.new;
  const loading = LoadFooBlocStateLoading.new;
  const failed = LoadFooBlocStateError.new;
  const success = LoadFooBlocStateSuccess.new;
  const reloadError = LoadFooBlocStateReloadError.new;

  test('states without data are equal by type', () {
    expect(idle(), idle());
    expect(loading(), loading());
  });

  test('states with data compare their fields', () {
    expect(failed(error: error), failed(error: error));
    expect(
      failed(error: error),
      isNot(failed(error: const NotFoundException())),
    );
    expect(success(foo: foo), isNot(success(foo: other)));
    expect(
      reloadError(foo: foo, error: error),
      reloadError(foo: foo, error: error),
    );
  });
}
