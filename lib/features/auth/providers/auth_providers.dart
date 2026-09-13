import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../core/services/supabase_service.dart';
import '../../../data/models/profile.dart';

/// Streams the current Supabase auth state so the router and UI can react
/// to login/logout/session-expiry immediately.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return SupabaseService.onAuthStateChange;
});

final currentUserIdProvider = Provider<String?>((ref) {
  final auth = ref.watch(authStateProvider);
  return auth.maybeWhen(
    data: (state) => state.session?.user.id,
    orElse: () => SupabaseService.currentUser?.id,
  );
});

final isAdminProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return false;
  try {
    final profile = await ref.watch(myProfileProvider.future);
    return profile.isAdmin;
  } catch (_) {
    return false;
  }
});

final myProfileProvider = FutureProvider<Profile>((ref) async {
  ref.watch(currentUserIdProvider);
  return ref.read(profileRepositoryProvider).getMyProfile();
});
