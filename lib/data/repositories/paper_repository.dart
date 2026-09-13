import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/supabase_service.dart';
import '../models/paper.dart';
import '../models/paper_section.dart';
import '../models/question.dart';

/// A paper section paired with its questions, in display order.
class SectionWithQuestions {
  final PaperSection section;
  final List<Question> questions;

  const SectionWithQuestions({required this.section, required this.questions});
}

class PaperRepository {
  /// Only PUBLISHED papers are ever returned to normal users; this is also
  /// enforced server-side via RLS, so this filter is defense-in-depth.
  Future<List<Paper>> getPapersForSubject({
    required String phaseId,
    required String subjectId,
  }) async {
    final cacheKey = '${AppConstants.cachePapersPrefix}${phaseId}_$subjectId';
    try {
      final rows = await SupabaseService.client
          .from('papers')
          .select()
          .eq('phase_id', phaseId)
          .eq('subject_id', subjectId)
          .eq('content_status', 'PUBLISHED')
          .order('created_at');
      final papers = rows.map((r) => Paper.fromJson(r)).toList();
      await CacheService.setJson(cacheKey, papers.map((p) => p.toJson()).toList());
      return papers;
    } catch (_) {
      final cached = CacheService.getJson<List<Paper>>(
        cacheKey,
        (decoded) => (decoded as List)
            .map((e) => Paper.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
      if (cached != null) return cached;
      throw AppException.network();
    }
  }

  Future<Paper> getPaper(String paperId) async {
    try {
      final row = await SupabaseService.client
          .from('papers')
          .select()
          .eq('id', paperId)
          .single();
      return Paper.fromJson(row);
    } catch (_) {
      throw AppException.notFound('This paper');
    }
  }

  /// Fetches full paper structure: sections -> questions -> options, in
  /// display order, for the Complete Solved Paper / section screens.
  ///
  /// Fetches sections and questions in exactly two queries regardless of
  /// how many sections the paper has — previously this ran one questions
  /// query per section (N+1: a paper with 5 sections meant 6 round trips
  /// just to render one screen). See docs/PERFORMANCE_AUDIT.md.
  Future<List<SectionWithQuestions>> getSectionsWithQuestions(
    String paperId,
  ) async {
    final cacheKey = '${AppConstants.cacheQuestionsPrefix}$paperId';
    try {
      final sectionRows = await SupabaseService.client
          .from('paper_sections')
          .select()
          .eq('paper_id', paperId)
          .order('display_order');
      final sections = sectionRows.map((r) => PaperSection.fromJson(r)).toList();

      final questionsBySectionId = <String, List<Question>>{};
      if (sections.isNotEmpty) {
        final qRows = await SupabaseService.client
            .from('questions')
            .select('*, question_options(*)')
            .inFilter('paper_section_id', sections.map((s) => s.id).toList())
            .order('display_order');
        for (final row in qRows) {
          final question = Question.fromJson(row);
          questionsBySectionId.putIfAbsent(question.paperSectionId, () => []).add(question);
        }
      }

      final result = sections
          .map((section) => SectionWithQuestions(
                section: section,
                questions: questionsBySectionId[section.id] ?? const [],
              ))
          .toList();

      await CacheService.setJson(
        cacheKey,
        result
            .map((r) => {
                  'section': r.section.toJson(),
                  'questions': r.questions.map((q) => q.toJson()).toList(),
                })
            .toList(),
      );
      return result;
    } catch (_) {
      final cached = CacheService.getJson<List<SectionWithQuestions>>(
        cacheKey,
        (decoded) => (decoded as List)
            .map((e) {
              final map = e as Map<String, dynamic>;
              return SectionWithQuestions(
                section: PaperSection.fromJson(map['section'] as Map<String, dynamic>),
                questions: (map['questions'] as List)
                    .map((q) => Question.fromJson(q as Map<String, dynamic>))
                    .toList(),
              );
            })
            .toList(),
      );
      if (cached != null) return cached;
      throw AppException.network();
    }
  }
}
