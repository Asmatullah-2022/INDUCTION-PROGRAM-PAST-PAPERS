import '../../core/errors/app_exception.dart';
import '../../core/services/supabase_service.dart';
import '../models/question.dart';

class PracticeRepository {
  /// Fetches up to [limit] published MCQs for the given phase/subject,
  /// shuffled for a practice session. Pass null for "All".
  Future<List<Question>> getPracticeQuestions({
    required String phaseId,
    required String subjectId,
    int? limit,
  }) async {
    final rows = await SupabaseService.client
        .from('questions')
        .select('*, question_options(*), paper_sections!inner(paper_id, papers!inner(phase_id, subject_id, content_status))')
        .eq('question_type', 'mcq')
        .eq('paper_sections.papers.phase_id', phaseId)
        .eq('paper_sections.papers.subject_id', subjectId)
        .eq('paper_sections.papers.content_status', 'PUBLISHED');

    final questions = rows.map((r) => Question.fromJson(r)).toList()..shuffle();
    if (limit != null && limit < questions.length) {
      return questions.sublist(0, limit);
    }
    return questions;
  }

  Future<String> startAttempt({
    required String phaseId,
    required String subjectId,
    required int totalQuestions,
  }) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) throw AppException.sessionExpired();
    final row = await SupabaseService.client
        .from('practice_attempts')
        .insert({
          'user_id': userId,
          'phase_id': phaseId,
          'subject_id': subjectId,
          'total_questions': totalQuestions,
          'correct_count': 0,
          'incorrect_count': 0,
          'skipped_count': 0,
          'started_at': DateTime.now().toIso8601String(),
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> submitAttempt({
    required String attemptId,
    required List<Map<String, dynamic>> answers, // question_id, selected_option_label?, is_correct, is_skipped
    required int correctCount,
    required int incorrectCount,
    required int skippedCount,
  }) async {
    if (answers.isNotEmpty) {
      await SupabaseService.client.from('practice_answers').insert(
        answers.map((a) => {...a, 'attempt_id': attemptId}).toList(),
      );
    }
    await SupabaseService.client.from('practice_attempts').update({
      'correct_count': correctCount,
      'incorrect_count': incorrectCount,
      'skipped_count': skippedCount,
      'completed_at': DateTime.now().toIso8601String(),
    }).eq('id', attemptId);
  }
}
