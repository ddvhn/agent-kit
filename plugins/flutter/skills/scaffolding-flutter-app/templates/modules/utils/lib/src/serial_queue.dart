/// Runs async tasks one at a time, in the order they were added; a failed
/// task fails only its own future (an upload queue, ordered writes).
final class SerialQueue {
  Future<void> _tail = Future.value();

  Future<T> add<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
