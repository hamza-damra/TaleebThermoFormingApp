import 'package:flutter/foundation.dart';

/// Build/runtime environment for the Palletizing app.
enum AppEnvironment { production, staging, debug }

/// Centralized backend configuration.
///
/// Production builds default to https://taleeb.me with normal TLS validation.
/// Staging builds (signalled by --dart-define=APP_ENV=staging) default to
/// https://138.68.66.215 and may opt-in to accepting the staging server's
/// self-signed certificate via --dart-define=ALLOW_STAGING_SELF_SIGNED_CERT=true.
///
/// The bad-cert override is intentionally double-gated: the environment must
/// NOT be production AND the host must be in [stagingTlsHosts]. A forgotten
/// dart-define on a release build can never silently enable staging TLS bypass.
class AppConfig {
  // ── Dart-define inputs ────────────────────────────────────────────────────
  static const String _appEnvRaw =
      String.fromEnvironment('APP_ENV', defaultValue: '');
  static const String _apiBaseUrlOverride =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');
  /// Empty string means "operator did not pass the dart-define" — in that case
  /// we infer the right answer from the environment + host. Explicit `true` or
  /// `false` always overrides the inferred value (subject to the production
  /// short-circuit).
  static const String _allowStagingRaw = String.fromEnvironment(
    'ALLOW_STAGING_SELF_SIGNED_CERT',
    defaultValue: '',
  );
  static const String _deviceKeyOverride =
      String.fromEnvironment('DEVICE_KEY', defaultValue: '');

  // ── Defaults ──────────────────────────────────────────────────────────────
  static const String _productionHost = 'https://taleeb.me';
  static const String _stagingHost = 'https://138.68.66.215';
  static const String _debugHost = 'http://hamzadamra.ddns.net:8080';

  /// API path prefix shared by ALL backend endpoints. Concrete endpoint paths
  /// (e.g. `/palletizing-line/bootstrap`) are appended by callers — this stays
  /// in [baseUrl] so existing repository code keeps working unchanged.
  static const String apiPrefix = '/api/v1';

  /// Hosts where the staging self-signed certificate is acceptable. The
  /// production host MUST NEVER appear here.
  static const Set<String> stagingTlsHosts = <String>{
    '138.68.66.215',
    'taleeb-staging.local',
  };

  // ── Timeouts ──────────────────────────────────────────────────────────────
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);

  /// Human-readable build tag rendered on the settings screen and emitted to
  /// adb logcat at startup.
  static const String buildLabel = 'palletizing-staging-2026-05-26';

  // ── Derived values ────────────────────────────────────────────────────────

  static AppEnvironment get environment {
    final v = _appEnvRaw.trim().toLowerCase();
    switch (v) {
      case 'production':
      case 'prod':
        return AppEnvironment.production;
      case 'staging':
      case 'stage':
        return AppEnvironment.staging;
      case 'debug':
      case 'dev':
      case 'development':
        return AppEnvironment.debug;
    }
    // Release builds with no APP_ENV default to production. Debug runs without
    // APP_ENV default to the local debug environment.
    return kReleaseMode ? AppEnvironment.production : AppEnvironment.debug;
  }

  static String envLabel() {
    switch (environment) {
      case AppEnvironment.production:
        return 'production';
      case AppEnvironment.staging:
        return 'staging';
      case AppEnvironment.debug:
        return 'debug';
    }
  }

  static String get _defaultServerBaseUrl {
    switch (environment) {
      case AppEnvironment.production:
        return _productionHost;
      case AppEnvironment.staging:
        return _stagingHost;
      case AppEnvironment.debug:
        return _debugHost;
    }
  }

  /// Scheme + host (no API prefix, no trailing slash). Used to derive [host]
  /// and to load product images from `<serverBaseUrl>/uploads/...` etc.
  static String get serverBaseUrl {
    final override = _apiBaseUrlOverride.trim();
    var raw = override.isNotEmpty ? override : _defaultServerBaseUrl;
    while (raw.endsWith('/')) {
      raw = raw.substring(0, raw.length - 1);
    }
    if (raw.endsWith(apiPrefix)) {
      raw = raw.substring(0, raw.length - apiPrefix.length);
    }
    return raw;
  }

  /// Full base URL used by Dio. Equivalent to the previous
  /// `https://taleeb.me/api/v1` constant.
  static String get baseUrl => '$serverBaseUrl$apiPrefix';

  /// Hostname of the current backend (no scheme, no port). Used by the TLS
  /// override host whitelist check.
  static String? get host {
    try {
      final h = Uri.parse(serverBaseUrl).host;
      return h.isEmpty ? null : h;
    } catch (_) {
      return null;
    }
  }

  /// True iff the staging self-signed TLS bypass should be active.
  ///
  /// Decision order:
  ///   1. Production builds are ALWAYS strict — short-circuit returns false.
  ///   2. Resolved baseUrl host must be in [stagingTlsHosts]. The bypass is
  ///      scoped to the whitelist regardless of caller intent.
  ///   3. If the operator explicitly passed
  ///      `--dart-define=ALLOW_STAGING_SELF_SIGNED_CERT=false` we honour the
  ///      opt-out and keep validation strict even on staging.
  ///   4. Otherwise (explicit `true` OR no dart-define) the bypass is enabled.
  ///      `flutter run` against `https://138.68.66.215` therefore Just Works
  ///      without remembering the dart-define, while production stays safe
  ///      because of gate 1 and the host whitelist.
  static bool get allowStagingSelfSignedCert {
    if (environment == AppEnvironment.production) return false;
    final h = host;
    if (h == null || !stagingTlsHosts.contains(h)) return false;
    final raw = _allowStagingRaw.trim().toLowerCase();
    if (raw == 'false' || raw == '0' || raw == 'no') return false;
    return true;
  }

  /// Optional device key supplied at build time. Most installs still use the
  /// device-settings screen; this is only an escape hatch for CI / smoke tests.
  static String? get deviceKeyOverride =>
      _deviceKeyOverride.isEmpty ? null : _deviceKeyOverride;
}
