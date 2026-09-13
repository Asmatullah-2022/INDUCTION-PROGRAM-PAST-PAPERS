import '../../core/pagination/paginated_result.dart';
import '../../core/services/supabase_service.dart';
import '../models/question.dart';

class SearchResultItem {
  final Question question;
  final String phaseName;
  final String subjectName;

  const SearchResultItem({
    required this.question,
    required this.phaseName,
    required this.subjectName,
  });
}

class SearchRepository {
  /// Full-text-ish search across question text and explanations for
  /// published content only, server-side (the `ilike` filter and the
  /// `content_status` join both run in Postgres — this never downloads
  /// the question table and filters it in Flutter) and backed by the
  /// trigram indexes in 005_indexes.sql.
  ///
  /// Offset-paginated (not keyset — search result ranking has no stable
  /// sort key to key off, unlike the time-ordered admin lists) so a
  /// "Load more" action fetches only the next [limit] results instead of
  /// re-running the whole query with a bigger limit. Kept as a page
  /// count matching [PaginatedResult.hasMore]'s "N+1 rows" technique.
  Future<PaginatedResult<SearchResultItem>> search(
    String query, {
    int offset = 0,
    int limit = 20,
  }) async {
    if (query.trim().length < 2) {
      return const PaginatedResult(items: [], hasMore: false);
    }
    final rows = await SupabaseService.client
        .from('questions')
        .select(
          '*, question_options(*), paper_sections!inner(paper_id, papers!inner(content_status, phases(name), subjects(name)))',
        )
        .eq('paper_sections.papers.content_status', 'PUBLISHED')
        .or('question_text.ilike.%$query%,explanation.ilike.%$query%')
        .range(offset, offset + limit);

    final hasMore = rows.length > limit;
    final page = hasMore ? rows.sublist(0, limit) : rows;
    final items = page.map((r) {
      final paperSection = r['paper_sections'] as Map<String, dynamic>;
      final paper = paperSection['papers'] as Map<String, dynamic>;
      final phase = paper['phases'] as Map<String, dynamic>?;
      final subject = paper['subjects'] as Map<String, dynamic>?;
      return SearchResultItem(
        question: Question.fromJson(r),
        phaseName: phase?['name'] as String? ?? '',
        subjectName: subject?['name'] as String? ?? '',
      );
    }).toList();
    return PaginatedResult(items: items, hasMore: hasMore);
  }
}
