import 'package:data/src/repository/foo_repository_impl.dart';
import 'package:domain/domain_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns the placeholder until the first data source', () async {
    expect(await FooRepositoryImpl().fetchFoo(), const Foo(id: 'foo'));
  });
}
