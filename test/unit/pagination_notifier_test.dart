import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:induction_program_past_papers/core/pagination/paginated_result.dart';
import 'package:induction_program_past_papers/core/pagination/pagination_notifier.dart';
import 'package:induction_program_past_papers/core/pagination/pagination_state.dart';

/// A fake paginated source: keyset-cursor based (the cursor is just "how
/// many pages already returned", as a string) — enough to exercise
/// first/next/last/empty without a real database. [callLog] records
/// every cursor actually requested, so a test can assert exactly how
/// many fetches happened — the pure-logic equivalent of an N+1
/// regression check (see docs/PERFORMANCE_AUDIT.md for why
/// repository-level query counts can't be verified without a live
/// Supabase project).
class _FakeNotifier extends PaginationNotifier<int> {
  List<List<int>> pages = const [];
  final List<String?> callLog = [];
  int? failOnCall;
  Completer<void>? gate;

  @override
  int get pageSize => 2;

  @override
  Future<PaginatedResult<int>> fetchPage(String? cursor, int limit) async {
    callLog.add(cursor);
    if (gate != null) await gate!.future;
    if (failOnCall != null && callLog.length == failOnCall) {
      throw StateError('simulated failure');
    }
    final pageIndex = cursor == null ? 0 : int.parse(cursor);
    if (pageIndex >= pages.length) {
      return const PaginatedResult(items: [], hasMore: false);
    }
    final isLast = pageIndex == pages.length - 1;
    return PaginatedResult(
      items: pages[pageIndex],
      hasMore: !isLast,
      nextCursor: isLast ? null : (pageIndex + 1).toString(),
    );
  }
}

final _testProvider = NotifierProvider<_FakeNotifier, PaginationState<int>>(_FakeNotifier.new);

/// Builds a fresh container + mounted notifier per test, with [pages] set
/// before any fetch can run (see the file-level note in PaginationNotifier
/// about why this ordering is safe against its own build()-time auto-load).
({ProviderContainer container, _FakeNotifier notifier}) _create(List<List<int>> pages) {
  final container = ProviderContainer();
  final notifier = container.read(_testProvider.notifier);
  notifier.pages = pages;
  return (container: container, notifier: notifier);
}

void main() {
  group('PaginationNotifier — first page', () {
    test('loads the first page and marks hasMore when more pages remain', () async {
      final ctx = _create([
        [1, 2],
        [3, 4],
      ]);
      addTearDown(ctx.container.dispose);

      await ctx.notifier.loadFirstPage();

      expect(ctx.notifier.state.items, [1, 2]);
      expect(ctx.notifier.state.hasMore, isTrue);
      expect(ctx.notifier.state.isLoading, isFalse);
      expect(ctx.notifier.callLog, [null]);
    });
  });

  group('PaginationNotifier — next page and last page', () {
    test('loadMore appends the next page and stops fetching once hasMore is false', () async {
      final ctx = _create([
        [1, 2],
        [3, 4],
        [5],
      ]);
      addTearDown(ctx.container.dispose);

      await ctx.notifier.loadFirstPage();
      await ctx.notifier.loadMore();
      expect(ctx.notifier.state.items, [1, 2, 3, 4]);
      expect(ctx.notifier.state.hasMore, isTrue);

      await ctx.notifier.loadMore();
      expect(ctx.notifier.state.items, [1, 2, 3, 4, 5]);
      expect(ctx.notifier.state.hasMore, isFalse); // that was the last page

      // Calling loadMore again once hasMore is false must not fetch again.
      await ctx.notifier.loadMore();
      expect(ctx.notifier.callLog.length, 3);
      expect(ctx.notifier.state.items, [1, 2, 3, 4, 5]); // no duplicates appended
    });
  });

  group('PaginationNotifier — empty result', () {
    test('an empty first page is not an error and reports hasMore = false', () async {
      final ctx = _create(const []);
      addTearDown(ctx.container.dispose);

      await ctx.notifier.loadFirstPage();

      expect(ctx.notifier.state.items, isEmpty);
      expect(ctx.notifier.state.hasMore, isFalse);
      expect(ctx.notifier.state.error, isNull);
    });
  });

  group('PaginationNotifier — concurrent load-more prevention', () {
    test('a loadMore already in flight blocks a second concurrent call', () async {
      final ctx = _create([
        [1, 2],
        [3, 4],
      ]);
      addTearDown(ctx.container.dispose);
      await ctx.notifier.loadFirstPage();

      ctx.notifier.gate = Completer<void>();
      final first = ctx.notifier.loadMore();
      final second = ctx.notifier.loadMore(); // must be a no-op, not a second fetch
      ctx.notifier.gate!.complete();
      await first;
      await second;

      expect(ctx.notifier.callLog, [null, '1']); // exactly one loadMore fetch
      expect(ctx.notifier.state.items, [1, 2, 3, 4]); // no duplicated page
    });

    test('concurrent calls to loadFirstPage share the same in-flight request', () async {
      final ctx = _create([
        [1, 2],
      ]);
      addTearDown(ctx.container.dispose);

      ctx.notifier.gate = Completer<void>();
      final a = ctx.notifier.loadFirstPage();
      final b = ctx.notifier.loadFirstPage();
      ctx.notifier.gate!.complete();
      await a;
      await b;

      expect(ctx.notifier.callLog, [null]); // only one fetch, not two
    });
  });

  group('PaginationNotifier — error recovery', () {
    test('a failed first-page load surfaces the error without crashing, and refresh recovers', () async {
      final ctx = _create([
        [1, 2],
      ]);
      addTearDown(ctx.container.dispose);

      ctx.notifier.failOnCall = 1;
      await ctx.notifier.loadFirstPage();

      expect(ctx.notifier.state.error, isNotNull);
      expect(ctx.notifier.state.items, isEmpty);
      expect(ctx.notifier.state.isLoading, isFalse);

      ctx.notifier.failOnCall = null;
      await ctx.notifier.refresh();

      expect(ctx.notifier.state.error, isNull);
      expect(ctx.notifier.state.items, [1, 2]);
    });

    test('a failed loadMore keeps the already-loaded items and clears isLoadingMore', () async {
      final ctx = _create([
        [1, 2],
        [3, 4],
      ]);
      addTearDown(ctx.container.dispose);

      await ctx.notifier.loadFirstPage();
      ctx.notifier.failOnCall = 2;
      await ctx.notifier.loadMore();

      expect(ctx.notifier.state.items, [1, 2]); // unchanged, not partially appended
      expect(ctx.notifier.state.error, isNotNull);
      expect(ctx.notifier.state.isLoadingMore, isFalse);
    });
  });

  group('PaginationNotifier — refresh', () {
    test('refresh re-fetches from the start even after pages have already been loaded', () async {
      final ctx = _create([
        [1, 2],
        [3, 4],
      ]);
      addTearDown(ctx.container.dispose);

      await ctx.notifier.loadFirstPage();
      await ctx.notifier.loadMore();
      expect(ctx.notifier.state.items, [1, 2, 3, 4]);

      await ctx.notifier.refresh();

      expect(ctx.notifier.state.items, [1, 2]); // back to just the first page
      expect(ctx.notifier.callLog, [null, '1', null]);
    });
  });
}
