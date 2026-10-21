// Use-case contracts for ui and the composition root; implementations stay
// hidden. data never imports this file (tool/check_layers.dart).
export 'package:domain/src/common/usecase/callable_use_case.dart';
export 'package:domain/src/di.dart';
export 'package:domain/src/foo/usecase/fetch_foo_use_case.dart'
    hide FetchFooUseCaseImpl;
