/// Connection details for the Duet backend.
///
/// The publishable key is **designed to be public** — it identifies the project
/// and nothing more. Every row it can reach is guarded by Row Level Security,
/// which is why supabase/tests/rls_test.sql exists and why it tests an attacker
/// rather than only the happy path. Shipping this key in the APK is expected.
///
/// What must NEVER appear here, or anywhere in this repo, is the `service_role`
/// key: that one bypasses RLS entirely and would hand any user the whole
/// database. It belongs only in Edge Functions and CI secrets.
///
/// Both values can still be overridden at build time without editing the file:
///   flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://htxxjvmikxgagtuuoxkm.supabase.co',
  );

  static const publishableKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_c-KyDimcLEDDkG8cTqfaEQ_XoxeADVR',
  );
}
