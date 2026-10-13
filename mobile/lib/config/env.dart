import 'package:flutter/services.dart' show appFlavor;

/// Build-time configuration, injected with `--dart-define-from-file=env/<name>.json`
/// (examples in `env/*.example.json`). Every value has a working default, so a plain
/// `flutter build apk --flavor direct` produces a usable app.
///
/// There is no server: jobs come from the data pipeline's files on GitHub, matching and
/// the exam watcher run on the phone, and the only account is Google (for the Drive backup).
abstract final class Env {
  /// The *Web application* OAuth client ID from Google Cloud ("serverClientId").
  /// A public identifier, not a secret. Empty = this build has no Google sign-in,
  /// so the app runs without backup.
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static bool get canSignIn => googleServerClientId.isNotEmpty;

  /// Where the data pipeline publishes jobs.json / notices.json (the repo's `data`
  /// branch). No server needed: the phone matches jobs itself.
  static const _dataBaseUrl = String.fromEnvironment(
    'DATA_BASE_URL',
    defaultValue: 'https://raw.githubusercontent.com/AnubhavSingh0603/exam-tracker/data',
  );

  static String get dataBaseUrl =>
      _dataBaseUrl.endsWith('/') ? _dataBaseUrl.substring(0, _dataBaseUrl.length - 1) : _dataBaseUrl;

  /// Calendar events are written in this zone. The audience is India-only, so
  /// a fixed zone avoids a native timezone-lookup dependency.
  static const timeZone = String.fromEnvironment('TIME_ZONE', defaultValue: 'Asia/Kolkata');

  /// The in-app updater's source, e.g.
  /// https://github.com/OWNER/REPO/releases/latest/download/latest.json
  static const releaseManifestUrl = String.fromEnvironment('RELEASE_MANIFEST_URL');

  /// Human-readable download page (opened if in-app install is blocked).
  static const releasesPageUrl = String.fromEnvironment('RELEASES_PAGE_URL');

  /// Self-updating is only for the `direct` (GitHub / website) build. Store builds
  /// are updated by their store, and stores generally reject self-updating apps.
  static bool get updatesEnabled => appFlavor == 'direct';
}
