import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/supabase_service.dart';
import '../models/subject.dart';

class SubjectRepository {
  Future<List<Subject>> getSubjects() async {
    try {
      final rows = await SupabaseService.client
          .from('subjects')
          .select()
          .eq('is_active', true)
          .order('display_order');
      final subjects = rows.map((r) => Subject.fromJson(r)).toList();
      await CacheService.setJson(
        AppConstants.cacheSubjectsKey,
        subjects.map((s) => s.toJson()).toList(),
      );
      return subjects;
    } catch (_) {
      final cached = CacheService.getJson<List<Subject>>(
        AppConstants.cacheSubjectsKey,
        (decoded) => (decoded as List)
            .map((e) => Subject.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
      if (cached != null && cached.isNotEmpty) return cached;
      throw AppException.network();
    }
  }
}
