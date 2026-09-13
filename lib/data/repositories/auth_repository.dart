import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/downloads_service.dart';
import '../../core/services/supabase_service.dart';

class AuthRepository {
  SupabaseClient get _client => SupabaseService.client;

  Future<void> signUp({
    required String fullName,
    required String email,
    required String mobileNumber,
    required String district,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'mobile_number': mobileNumber,
          'district': district,
        },
      );
      final user = response.user;
      if (user != null) {
        // profiles row is created by a DB trigger (handle_new_user) from
        // the auth metadata above; nothing else to do client-side.
      }
    } on AuthException catch (e) {
      throw AppException.auth(_mapAuthError(e.message));
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      throw AppException.auth(_mapAuthError(e.message));
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
    } on AuthException catch (e) {
      throw AppException.auth(_mapAuthError(e.message));
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw AppException.auth(_mapAuthError(e.message));
    }
  }

  /// Deletes the user's own account data and account via a Supabase Edge
  /// Function invoked with the user's own JWT (the client never holds a
  /// service-role key, so the destructive delete must happen server-side).
  /// Also wipes local device state (cached content, downloaded PDFs) so
  /// nothing tied to the now-deleted account lingers on the device after
  /// sign-out — best-effort: a local-cleanup failure never blocks the
  /// account deletion itself, since the server-side deletion already
  /// succeeded by the time cleanup runs.
  Future<void> deleteAccount() async {
    try {
      await _client.functions.invoke('delete-account');
      await _client.auth.signOut();
    } catch (e) {
      throw const AppException(
        'Could not delete your account right now. Please try again later.',
      );
    }
    try {
      await DownloadsService.clearAll();
      await CacheService.clearAll();
    } catch (_) {
      // Best-effort local cleanup — the account is already deleted server-side.
    }
  }

  String _mapAuthError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('invalid login credentials')) {
      return 'Incorrect email or password.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Please confirm your email address before logging in.';
    }
    if (lower.contains('already registered') || lower.contains('already exists')) {
      return 'An account with this email already exists.';
    }
    if (lower.contains('password') && lower.contains('least')) {
      return 'Password must be at least 6 characters.';
    }
    return message;
  }
}
