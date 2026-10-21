import 'package:domain/domain_model.dart';
import 'package:domain/domain_repository.dart';

/// Empty until the first data source: a backend (calling-cloud-functions)
/// and a local cache (persisting-with-isar) replace the placeholder value.
final class FooRepositoryImpl implements FooRepository {
  @override
  Future<Foo> fetchFoo() async => const Foo(id: 'foo');
}
