import 'package:equatable/equatable.dart';

sealed class Session extends Equatable {
  const Session();

  @override
  List<Object?> get props => const [];
}

final class SessionSignedOut extends Session {
  const SessionSignedOut();
}

final class SessionSignedIn extends Session {
  const SessionSignedIn({required this.userId});

  final String userId;

  @override
  List<Object?> get props => [userId];
}
