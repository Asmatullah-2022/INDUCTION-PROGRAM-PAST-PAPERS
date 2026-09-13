import '../../core/errors/app_exception.dart';
import '../../core/services/supabase_service.dart';
import '../models/bookmark.dart';

class BookmarkRepository {
  Future<List<Bookmark>> getMyBookmarks({BookmarkTargetType? type}) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) throw AppException.sessionExpired();
    var query = SupabaseService.client.from('bookmarks').select().eq('user_id', userId);
    if (type != null) {
      query = query.eq('target_type', type.dbValue);
    }
    final rows = await query.order('created_at', ascending: false);
    return rows.map((r) => Bookmark.fromJson(r)).toList();
  }

  Future<bool> isBookmarked({
    required BookmarkTargetType type,
    required String targetId,
  }) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return false;
    final rows = await SupabaseService.client
        .from('bookmarks')
        .select('id')
        .eq('user_id', userId)
        .eq('target_type', type.dbValue)
        .eq('target_id', targetId)
        .limit(1);
    return rows.isNotEmpty;
  }

  Future<void> toggleBookmark({
    required BookmarkTargetType type,
    required String targetId,
  }) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) throw AppException.sessionExpired();
    final existing = await SupabaseService.client
        .from('bookmarks')
        .select('id')
        .eq('user_id', userId)
        .eq('target_type', type.dbValue)
        .eq('target_id', targetId)
        .limit(1);
    if (existing.isNotEmpty) {
      await SupabaseService.client
          .from('bookmarks')
          .delete()
          .eq('id', existing.first['id']);
    } else {
      await SupabaseService.client.from('bookmarks').insert({
        'user_id': userId,
        'target_type': type.dbValue,
        'target_id': targetId,
      });
    }
  }
}
