/// Where a read comes from (the stack `data` rule owns the semantics).
enum CachePolicy {
  /// Local copy only; nothing stored throws `NotFoundException`.
  cache,

  /// Network, unless the in-memory copy is still fresh; the result is saved.
  network,

  /// Local copy if any (even stale), otherwise network.
  networkIfNotCached,

  /// Always the network (concurrent requests still share one call); the
  /// result is saved. A user's explicit refresh, such as pull-to-refresh.
  refresh,
}
