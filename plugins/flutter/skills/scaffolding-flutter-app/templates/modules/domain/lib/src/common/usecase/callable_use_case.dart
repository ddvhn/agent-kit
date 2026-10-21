mixin CallableUseCase<Params, Result> {
  Future<Result> call(Params params);
}

mixin CallableUseCaseSync<Params, Result> {
  Result call(Params params);
}

mixin CallableUseCaseWithoutParams<Result> {
  Future<Result> call();
}

mixin CallableUseCaseWithoutParamsSync<Result> {
  Result call();
}
