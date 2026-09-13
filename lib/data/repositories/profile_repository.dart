import '../../core/errors/app_exception.dart';
import '../../core/services/supabase_service.dart';
import '../models/profile.dart';

class ProfileRepository {
  Future<Profile> getMyProfile() async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) throw AppException.sessionExpired();
    try {
      final row = await SupabaseService.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      return Profile.fromJson(row);
    } catch (_) {
      throw AppException.notFound('Your profile');
    }
  }

  Future<void> updateProfile({
    required String fullName,
    String? mobileNumber,
    String? district,
  }) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) throw AppException.sessionExpired();
    try {
      await SupabaseService.client.from('profiles').update({
        'full_name': fullName,
        'mobile_number': mobileNumber,
        'district': district,
      }).eq('id', userId);
    } catch (_) {
      throw AppException.server();
    }
  }
}
