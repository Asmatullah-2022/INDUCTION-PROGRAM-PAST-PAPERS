# Keep Supabase/Gotrue/Realtime models and pdfx/photo_view working under
# R8 minification. Flutter's own plugin registrant classes are kept
# automatically by the Flutter Gradle plugin's default rules.
-keep class io.supabase.** { *; }
-keep class com.google.crypto.tink.** { *; }
-dontwarn okhttp3.**
-dontwarn org.conscrypt.**
