final class PageResult<T> {
  const PageResult({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<T> items;
  final bool hasMore;

  /// Opaque server continuation context; some feeds use a batch anchor.
  final String? nextCursor;
}
