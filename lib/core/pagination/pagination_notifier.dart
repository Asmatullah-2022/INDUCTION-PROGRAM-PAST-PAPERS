import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'paginated_result.dart';
import 'pagination_state.dart';

/// Base Riverpod [Notifier] for a server-side-paginated list. Concrete
/// screens subclass this and implement [fetchPage] against their own
/// repository — everything else (first-page load, load-more, refresh,
/// duplicate-request prevention) is handled once here rather than
/// reimplemented per screen.
///
/// [fetchPage] receives the opaque cursor from the previous page's
/// [PaginatedResult.nextCursor] (`null` for the first page) — this is
/// keyset pagination, not offset pagination, so a row inserted while the
/// user is scrolling never shifts already-fetched pages. See
/// docs/PERFORMANCE_AUDIT.md for why keyset was chosen over offset here.
abstract class PaginationNotifier<T> extends Notifier<PaginationState<T>> {
  int get pageSize => 20;

  Future<PaginatedResult<T>> fetchPage(String? cursor, int limit);

  /// Guards against calling [loadFirstPage] twice concurrently (e.g. the
  /// notifier's own auto-load on [build] racing an explicit call from a
  /// widget) by returning the same in-flight future to every caller
  /// instead of starting a second fetch.
  Future<void>? _pendingFirstPage;

  @override
  PaginationState<T> build() {
    Future.microtask(loadFirstPage);
    return const PaginationState();
  }

  Future<void> loadFirstPage() {
    return _pendingFirstPage ??= _doLoadFirstPage().whenComplete(() {
      _pendingFirstPage = null;
    });
  }

  Future<void> _doLoadFirstPage() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final page = await fetchPage(null, pageSize);
      state = PaginationState<T>(
        items: page.items,
        hasMore: page.hasMore,
        cursor: page.nextCursor,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// No-ops if a load is already in flight or there is nothing more to
  /// load — safe to wire directly to a scroll-end listener without an
  /// extra guard at the call site.
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final page = await fetchPage(state.cursor, pageSize);
      state = state.copyWith(
        items: [...state.items, ...page.items],
        isLoadingMore: false,
        hasMore: page.hasMore,
        cursor: page.nextCursor,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  /// Pull-to-refresh: discards the current pages and re-fetches from the
  /// start, even if a first-page load already completed.
  Future<void> refresh() {
    _pendingFirstPage = null;
    return loadFirstPage();
  }
}
