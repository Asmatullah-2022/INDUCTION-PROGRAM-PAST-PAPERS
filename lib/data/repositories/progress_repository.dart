import '../../core/errors/app_exception.dart';
import '../../core/services/supabase_service.dart';
import '../models/user_progress.dart';

class ProgressRepository {
  Future<List<UserProgress>> getMyProgress() async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) throw AppException.sessionExpired();
    final rows = await SupabaseService.client
        .from('user_progress')
        .select()
        .eq('user_id', userId);
    return rows.map((r) => UserProgress.fromJson(r)).toList();
  }

  /// Upserts progress for one phase/subject after a practice attempt or
  /// completed paper. Server-side RLS restricts writes to the owning user.
  Future<void> upsertProgress({
    required String phaseId,
    required String subjectId,
    required int attemptedDelta,
    required int correctDelta,
    required int incorrectDelta,
  }) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) throw AppException.sessionExpired();

    final existing = await SupabaseService.client
        .from('user_progress')
        .select()
        .eq('user_id', userId)
        .eq('phase_id', phaseId)
        .eq('subject_id', subjectId)
        .maybeSingle();

    if (existing == null) {
      await SupabaseService.client.from('user_progress').insert({
        'user_id': userId,
        'phase_id': phaseId,
        'subject_id': subjectId,
        'attempted_count': attemptedDelta,
        'correct_count': correctDelta,
        'incorrect_count': incorrectDelta,
        'completed_papers_count': 0,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } else {
      await SupabaseService.client.from('user_progress').update({
        'attempted_count': (existing['attempted_count'] as num? ?? 0) + attemptedDelta,
        'correct_count': (existing['correct_count'] as num? ?? 0) + correctDelta,
        'incorrect_count': (existing['incorrect_count'] as num? ?? 0) + incorrectDelta,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', existing['id']);
    }
  }
}
