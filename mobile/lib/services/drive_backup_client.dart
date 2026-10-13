import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Drive said the app needs the user's permission again (revoked, or never granted).
class DrivePermissionRequired implements Exception {
  const DrivePermissionRequired();
}

class DriveException implements Exception {
  const DriveException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;

  @override
  String toString() => 'DriveException($statusCode): $message';
}

/// The backup file found in the app folder.
class DriveFile {
  const DriveFile(this.id, this.modifiedTime);
  final String id;
  final DateTime? modifiedTime;
}

/// Minimal Google Drive v3 client for one file in the hidden app folder
/// (`appDataFolder`): only this app can see it, and it doesn't count as the
/// user's own files. Plain REST over `http`, so no extra packages.
class DriveBackupClient {
  DriveBackupClient({
    required Future<Map<String, String>?> Function() authHeaders,
    required Future<void> Function(String authorization) onRejectedToken,
    http.Client? client,
  })  : _authHeaders = authHeaders,
        _onRejectedToken = onRejectedToken,
        _client = client ?? http.Client();

  final Future<Map<String, String>?> Function() _authHeaders;
  final Future<void> Function(String authorization) _onRejectedToken;
  final http.Client _client;

  static const fileName = 'exam-tracker-backup.json';
  static const _api = 'https://www.googleapis.com/drive/v3/files';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3/files';
  static const _timeout = Duration(seconds: 30);

  Future<DriveFile?> find() async {
    final uri = Uri.parse(_api).replace(queryParameters: {
      'spaces': 'appDataFolder',
      'q': "name = '$fileName' and trashed = false",
      'fields': 'files(id, modifiedTime)',
      'orderBy': 'modifiedTime desc',
      'pageSize': '1',
    });
    final res = await _send(() => http.Request('GET', uri));
    final files =
        (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['files'] as List<dynamic>? ?? [];
    if (files.isEmpty) return null;
    final f = files.first as Map<String, dynamic>;
    return DriveFile(f['id'] as String, DateTime.tryParse(f['modifiedTime'] as String? ?? ''));
  }

  Future<String> download(String id) async {
    final res = await _send(
        () => http.Request('GET', Uri.parse('$_api/$id').replace(queryParameters: {'alt': 'media'})));
    return utf8.decode(res.bodyBytes);
  }

  /// Creates the file, or overwrites it when [existingId] is given. Returns its id.
  Future<String> upload(String json, {String? existingId}) async {
    if (existingId != null) {
      final res = await _send(() => http.Request(
            'PATCH',
            Uri.parse('$_upload/$existingId')
                .replace(queryParameters: {'uploadType': 'media', 'fields': 'id'}),
          )
            ..headers['Content-Type'] = 'application/json; charset=utf-8'
            ..bodyBytes = utf8.encode(json));
      return (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['id'] as String? ?? existingId;
    }
    final boundary = 'exam-tracker-${Random.secure().nextInt(1 << 32)}';
    final metadata = jsonEncode({
      'name': fileName,
      'parents': ['appDataFolder'],
      'mimeType': 'application/json',
    });
    final body = '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n'
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n$json\r\n'
        '--$boundary--';
    final res = await _send(() => http.Request(
          'POST',
          Uri.parse(_upload).replace(queryParameters: {'uploadType': 'multipart', 'fields': 'id'}),
        )
          ..headers['Content-Type'] = 'multipart/related; boundary=$boundary'
          ..bodyBytes = utf8.encode(body));
    return (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['id'] as String;
  }

  /// Sends with fresh auth headers; on 401 drops the token and retries once.
  Future<http.Response> _send(http.Request Function() build, {bool retried = false}) async {
    final headers = await _authHeaders();
    if (headers == null) throw const DrivePermissionRequired();
    final request = build()..headers.addAll(headers);
    final res = await http.Response.fromStream(await _client.send(request).timeout(_timeout));
    if (res.statusCode == 401 && !retried) {
      await _onRejectedToken(headers['Authorization'] ?? '');
      return _send(build, retried: true);
    }
    if (res.statusCode == 401 ||
        (res.statusCode == 403 &&
            RegExp('insufficient|PERMISSION_DENIED|forbidden', caseSensitive: false).hasMatch(res.body))) {
      throw const DrivePermissionRequired();
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw DriveException('Drive request failed (${res.statusCode})', res.statusCode);
    }
    return res;
  }

  void close() => _client.close();
}
