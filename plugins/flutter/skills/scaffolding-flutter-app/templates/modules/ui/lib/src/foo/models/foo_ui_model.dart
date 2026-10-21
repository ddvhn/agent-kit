import 'package:domain/domain_model.dart';
import 'package:equatable/equatable.dart';

final class FooUiModel extends Equatable {
  const FooUiModel({required this.id});

  factory FooUiModel.fromFoo(Foo foo) => FooUiModel(id: foo.id);

  final String id;

  @override
  List<Object?> get props => [id];
}
