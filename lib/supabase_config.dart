/// Supabase project credentials.
///
/// The **publishable key** is safe to ship inside a client app — it can only do
/// what your Row Level Security (RLS) policies allow. NEVER put the *secret* /
/// *service_role* key in the app.
///
/// Fill these in from your Supabase dashboard:
///   Project → Settings → API Keys
///     • Project URL          → [url]
///     • Publishable key (sb_publishable_…) → [publishableKey]
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = 'https://fadkprreszcttmjjybbz.supabase.co';
  static const String publishableKey = 'sb_publishable_W-NAPIdaQNDqH9fMSjy5Vw_ljgcRPhD';

  /// True once the placeholders above have been replaced with real values.
  static bool get isConfigured =>
      url != 'YOUR_SUPABASE_URL' &&
      publishableKey != 'YOUR_SUPABASE_PUBLISHABLE_KEY';
}
