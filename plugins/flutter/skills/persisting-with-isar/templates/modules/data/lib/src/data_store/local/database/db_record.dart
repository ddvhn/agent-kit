/// A cached remote payload and when it was saved; `dbTimestamp` feeds the
/// TTL (`data` rule, Caching).
final class DbRecord<Dto> {
  const DbRecord({required this.dto, required this.dbTimestamp});

  final Dto dto;
  final DateTime dbTimestamp;
}
