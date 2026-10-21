import 'package:domain/src/foo/model/foo.dart';

abstract interface class FooRepository {
  Future<Foo> fetchFoo();
}
