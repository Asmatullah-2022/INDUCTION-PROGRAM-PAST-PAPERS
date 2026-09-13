/// One server-fetched page of results, returned by a repository's
/// paginated fetch method. [nextCursor] is an opaque, repository-defined
/// string (e.g. an ISO-8601 timestamp for keyset pagination) — callers
/// never construct or parse it, only pass it back into the next fetch.
class PaginatedResult<T> {
  final List<T> items;
  final bool hasMore;
  final String? nextCursor;

  const PaginatedResult({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });
}
