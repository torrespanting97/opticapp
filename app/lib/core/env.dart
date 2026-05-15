/// Compile-time configuration. Pass with:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// In CI / release builds we use `--dart-define-from-file=env.json`.
class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://rcldmmanvvtkkrbwpkgk.supabase.co',
  );

  /// Either the new `sb_publishable_...` key (preferred) or the legacy anon JWT.
  /// Both are safe to ship inside the client binary.
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_7VMxKF0OFDWRYgM2DbFSkA_QdXi7x_d',
  );

  // Optional: Stripe publishable key for payment links
  static const stripePublishable =
      String.fromEnvironment('STRIPE_PUBLISHABLE_KEY', defaultValue: '');

  // Map tile server (OSM by default)
  static const tileUrl = String.fromEnvironment(
    'TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );
}
