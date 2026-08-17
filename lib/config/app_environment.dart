/// Which Supabase project this build talks to.
///
/// Selected once, at compile time, via:
///   --dart-define=OPTIMEAL_ENV=dev   (default — any build/run/test with no
///                                     flag at all resolves here)
///   --dart-define=OPTIMEAL_ENV=prod  (must be passed explicitly)
///
/// The CLI link (`supabase link`) points at the production project
/// regardless of this flag — this config only controls what the *client
/// app* connects to, not `supabase db push`/`functions deploy`. See
/// CLAUDE.md "Current architecture facts" and "Working conventions".
library;

/// Raw dart-define value, before validation. Kept as its own `const` so
/// [kIsDevEnvironment] below is independently compile-time-foldable —
/// that's what lets the release compiler tree-shake dev-only UI (the DEV
/// badge) out of a prod build entirely, the same mechanism `kDebugMode`
/// uses. Do not route [kIsDevEnvironment] through [AppEnvironmentConfig]'s
/// non-const validation logic, or that folding stops working.
const String _rawOptimealEnv = String.fromEnvironment('OPTIMEAL_ENV', defaultValue: 'dev');

/// True only when this build was compiled with `OPTIMEAL_ENV=dev` (or no
/// flag at all, since that's the default). A genuine compile-time constant
/// — safe to gate dev-only widgets behind (`if (kIsDevEnvironment) ...`)
/// with the guarantee that branch is stripped from prod builds, not just
/// hidden at runtime.
const bool kIsDevEnvironment = _rawOptimealEnv == 'dev';

enum AppEnvironment {
  dev,
  prod;

  bool get isDev => this == AppEnvironment.dev;
}

class SupabaseEnvironmentConfig {
  const SupabaseEnvironmentConfig({required this.url, required this.anonKey});

  final String url;
  final String anonKey;
}

/// Placeholder value for the dev Supabase project until Harris creates it
/// and pastes in the real URL/anon key below. Startup deliberately throws
/// if the app resolves to dev while this placeholder is still in place —
/// see [AppEnvironmentConfig.assertConfigured].
const String kDevCredentialsNotSetPlaceholder = 'DEV_URL_NOT_SET';

/// Resolves [AppEnvironment] from `OPTIMEAL_ENV` and exposes the matching
/// Supabase project config. Call [assertConfigured] once at the very start
/// of `main()`, before `Supabase.initialize(...)`.
class AppEnvironmentConfig {
  AppEnvironmentConfig._();

  static const Map<AppEnvironment, SupabaseEnvironmentConfig> _supabaseConfigs = {
    // Dev project (ref suuafglvrxrllnhipkiv), created 2026-08-17 in the same
    // org/region as production. See CLAUDE.md "Current architecture facts".
    AppEnvironment.dev: SupabaseEnvironmentConfig(
      url: 'https://suuafglvrxrllnhipkiv.supabase.co',
      anonKey: 'sb_publishable_iJ-WyzQZX6tBWjM6txf4iA_OAI4bq8W',
    ),
    // Production project (ref xwugnhzlnfgmczkbbcbh) — moved here verbatim
    // from the previous hardcoded constants in lib/main.dart.
    AppEnvironment.prod: SupabaseEnvironmentConfig(
      url: 'https://xwugnhzlnfgmczkbbcbh.supabase.co',
      anonKey: 'sb_publishable_fflcK-rDIAE4-wyuHLdjLw_IVrB7Rzn',
    ),
  };

  /// The active environment for this build. Throws a [StateError] with a
  /// clear message if `OPTIMEAL_ENV` was set to anything other than
  /// exactly `dev` or `prod` — never falls back silently.
  static final AppEnvironment environment = _resolveEnvironment();

  static AppEnvironment _resolveEnvironment() {
    switch (_rawOptimealEnv) {
      case 'dev':
        return AppEnvironment.dev;
      case 'prod':
        return AppEnvironment.prod;
      default:
        throw StateError(
          'Invalid OPTIMEAL_ENV value: "$_rawOptimealEnv". Must be exactly '
          '"dev" or "prod". Pass --dart-define=OPTIMEAL_ENV=prod for '
          'production, or omit the flag entirely for dev (the default).',
        );
    }
  }

  /// The Supabase project config for the active environment.
  static SupabaseEnvironmentConfig get supabase => _supabaseConfigs[environment]!;

  /// Throws a clear [StateError] if the app resolved to dev but the dev
  /// Supabase credentials are still the [kDevCredentialsNotSetPlaceholder]
  /// placeholder. Never throws for prod — its credentials are always real
  /// and committed. Call once, early in `main()`.
  static void assertConfigured() {
    if (!environment.isDev) return;
    final config = supabase;
    if (config.url == kDevCredentialsNotSetPlaceholder || config.anonKey == kDevCredentialsNotSetPlaceholder) {
      throw StateError(
        'OPTIMEAL_ENV resolved to dev, but the dev Supabase URL/anon key in '
        'lib/config/app_environment.dart are still the '
        '"$kDevCredentialsNotSetPlaceholder" placeholder. Create the dev '
        'Supabase project and paste its real URL + anon key into '
        'AppEnvironmentConfig._supabaseConfigs[AppEnvironment.dev] before '
        'running.',
      );
    }
  }

  /// A single, hard-to-miss console line naming the active environment.
  /// Call once, early in `main()`, after [assertConfigured].
  static void printStartupBanner() {
    // ignore: avoid_print
    print('▓▓▓ OPTIMEAL environment: ${environment.name.toUpperCase()} (Supabase project: ${supabase.url}) ▓▓▓');
  }
}
