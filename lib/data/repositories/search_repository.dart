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
  /// Full-text-ish search across question text, explanations, and MCQ
  /// options for published content only.
  Future<List<SearchResultItem>> search(String query) async {
    if (query.trim().length < 2) return [];
    final rows = await SupabaseService.client
        .from('questions')
        .select(
          '*, question_options(*), paper_sections!inner(paper_id, papers!inner(content_status, phases(name), subjects(name)))',
        )
        .eq('paper_sections.papers.content_status', 'PUBLISHED')
        .or('question_text.ilike.%$query%,explanation.ilike.%$query%')
        .limit(50);

    return rows.map((r) {
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
  }
}
