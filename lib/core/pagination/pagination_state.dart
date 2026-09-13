/// Immutable state for one server-paginated list: the items loaded so
/// far, whether the first page or a subsequent page is in flight, whether
/// more pages remain, and the last error (if any). Shared by every screen
/// that uses [PaginationNotifier] — see that file for the loading logic.
class PaginationState<T> {
  final List<T> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final String? cursor;

  const PaginationState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.cursor,
  });

  PaginationState<T> copyWith({
    List<T>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
    String? cursor,
  }) {
    return PaginationState<T>(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
      cursor: cursor ?? this.cursor,
    );
  }
}
