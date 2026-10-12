import 'package:flutter/services.dart' show appFlavor;

enum AppEnv { dev, staging, prod }

/// Build-time configuration, injected with `--dart-define-from-file=env.<name>.json`.
///
/// Pick the backend with `APP_ENV` (dev | staging | prod); each has its own URL key, and an
/// explicit `API_BASE_URL` overrides all of them. Examples live in `env/*.example.json`.
///
/// Auth modes
///  * Google sign-in (staging/prod and normal dev): needs `GOOGLE_SERVER_CLIENT_ID`.
///  * Dev API-key mode: set `API_KEY` (and optionally `USER_ID`) to skip Google while
///    testing against your own laptop. **Ignored when APP_ENV=prod**, so a key can never
///    ship inside a public APK by accident.
abstract final class Env {
  static const _envName = String.fromEnvironment('APP_ENV', defaultValue: 'prod');

  static AppEnv get appEnv =>
      AppEnv.values.firstWhere((e) => e.name == _envName, orElse: () => AppEnv.prod);

  static const _override = String.fromEnvironment('API_BASE_URL');
  // 10.0.2.2 is the host machine as seen from the Android emulator. On a real phone, use
  // your laptop's LAN IP instead, e.g. http://192.168.1.20:8000.
  static const _devUrl = String.fromEnvironment('API_BASE_URL_DEV', defaultValue: 'http://10.0.2.2:8000');
  static const _stagingUrl = String.fromEnvironment('API_BASE_URL_STAGING');
  static const _prodUrl = String.fromEnvironment('API_BASE_URL_PROD');

  static String get apiBaseUrl {
    final url = _override.isNotEmpty
        ? _override
        : switch (appEnv) {
            AppEnv.dev => _devUrl,
            AppEnv.staging => _stagingUrl,
            AppEnv.prod => _prodUrl,
          };
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  static const _apiKey = String.fromEnvironment('API_KEY');
  static const _userId = String.fromEnvironment('USER_ID');

  /// Shared-key testing mode (X-API-Key + profile id). Never active in prod builds.
  static bool get devKeyMode => _apiKey.isNotEmpty && appEnv != AppEnv.prod;
  static String get apiKey => devKeyMode ? _apiKey : '';
  static String get presetUserId => devKeyMode ? _userId : '';

  /// The *Web application* OAuth client ID (same value as the backend's GOOGLE_CLIENT_IDS).
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static bool get hasBackend => apiBaseUrl.isNotEmpty;
  static bool get canSignIn => hasBackend && !devKeyMode && googleServerClientId.isNotEmpty;

  /// Calendar events are written in this zone. The audience is India-only, so
  /// a fixed zone avoids a native timezone-lookup dependency.
  static const timeZone = String.fromEnvironment('TIME_ZONE', defaultValue: 'Asia/Kolkata');

  /// Fallback when the server is unreachable, e.g.
  /// https://github.com/OWNER/REPO/releases/latest/download/latest.json
  static const releaseManifestUrl = String.fromEnvironment('RELEASE_MANIFEST_URL');

  /// Human-readable download page (opened if in-app install is blocked).
  static const releasesPageUrl = String.fromEnvironment('RELEASES_PAGE_URL');

  /// Self-updating is only for the `direct` (GitHub / website) build. Store builds
  /// are updated by their store, and stores generally reject self-updating apps.
  static bool get updatesEnabled => appFlavor == 'direct';
}
