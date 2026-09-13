import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around the Supabase client. The app must only ever use the
/// anon/publishable key (SUPABASE_ANON_KEY) here — the service-role key
/// must never be embedded in the client application.
class SupabaseService {
  SupabaseService._();

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
      debug: false,
    );
  }

  static bool get _isInitialized {
    try {
      // Accessing Supabase.instance throws if initialize() was never
      // called (e.g. in widget tests that don't set up a backend).
      Supabase.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  static User? get currentUser => _isInitialized ? client.auth.currentUser : null;
  static bool get isLoggedIn => currentUser != null;
  static Stream<AuthState> get onAuthStateChange =>
      _isInitialized ? client.auth.onAuthStateChange : const Stream.empty();
}
