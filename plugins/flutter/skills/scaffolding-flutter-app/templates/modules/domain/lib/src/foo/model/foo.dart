import 'package:equatable/equatable.dart';

/// The example entity: rename it to the first real concept (modeling-domain).
final class Foo extends Equatable {
  const Foo({required this.id});

  final String id;

  @override
  List<Object?> get props => [id];
}
