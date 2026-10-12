import 'package:exam_tracker/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _sha = 'a3f1c2d4e5b6978877665544332211009988776655443322110099887766aabb';

void main() {
  test('release number survives the ×10 + ABI version-code scheme', () {
    expect(releaseNumberOf(40), 4); // universal
    expect(releaseNumberOf(42), 4); // arm64-v8a split of the same release
    expect(releaseNumberOf(50) > releaseNumberOf(43), isTrue); // newer universal beats older split
  });

  test('manifest picks the device ABI, falls back to universal', () {
    final manifest = {
      'version_code': 5,
      'version_name': '0.4.1',
      'min_supported_version_code': 2,
      'release_notes': 'Calmer hero card',
      'apks': {
        'universal': {'url': 'https://github.com/o/r/releases/download/v0.4.1/u.apk', 'sha256': _sha},
        'arm64-v8a': {'url': 'https://github.com/o/r/releases/download/v0.4.1/a64.apk', 'sha256': _sha, 'size_bytes': 9437184},
      },
    };
    final arm = UpdateInfo.fromManifest(manifest, 'arm64-v8a')!;
    expect(arm.apkUrl, endsWith('a64.apk'));
    expect(arm.sizeLabel, '9.0 MB');
    expect(UpdateInfo.fromManifest(manifest, 'x86')!.apkUrl, endsWith('u.apk'));
    expect(arm.isTrustworthy, isTrue);
  });

  test('server payload parses and untrustworthy assets are rejected', () {
    final info = UpdateInfo.fromServer({
      'latest_version_code': 5,
      'version_name': '0.4.1',
      'min_supported_version_code': 1,
      'release_notes': '',
      'apk_url': 'http://insecure.example/app.apk',
      'sha256': _sha,
    });
    expect(info.isTrustworthy, isFalse); // http, not https

    final noHash = UpdateInfo.fromServer({
      'latest_version_code': 5,
      'version_name': '0.4.1',
      'apk_url': 'https://example.org/app.apk',
      'sha256': 'not-a-hash',
    });
    expect(noHash.isTrustworthy, isFalse);
  });
}
