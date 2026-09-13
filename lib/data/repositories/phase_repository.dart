import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/supabase_service.dart';
import '../models/phase.dart';

class PhaseRepository {
  Future<List<Phase>> getPhases() async {
    try {
      final rows = await SupabaseService.client
          .from('phases')
          .select()
          .eq('is_active', true)
          .order('display_order');
      final phases = rows.map((r) => Phase.fromJson(r)).toList();
      await CacheService.setJson(
        AppConstants.cachePhasesKey,
        phases.map((p) => p.toJson()).toList(),
      );
      return phases;
    } catch (_) {
      final cached = CacheService.getJson<List<Phase>>(
        AppConstants.cachePhasesKey,
        (decoded) => (decoded as List)
            .map((e) => Phase.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
      if (cached != null && cached.isNotEmpty) return cached;
      throw AppException.network();
    }
  }
}
