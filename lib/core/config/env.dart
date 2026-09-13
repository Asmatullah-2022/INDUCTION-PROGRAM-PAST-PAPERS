/// Build-time configuration, supplied via --dart-define (never hard-coded,
/// never committed). Example:
///
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
///
/// SUPABASE_ANON_KEY is the public/publishable key by design — Supabase's
/// client architecture expects it in the app. The service-role key must
/// NEVER be passed here or embedded anywhere in the Flutter app.
class Env {
  Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
