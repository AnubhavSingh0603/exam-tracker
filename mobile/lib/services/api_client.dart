import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Returns a valid access token, refreshing first when [forceRefresh] or nearly expired.
typedef AccessTokenProvider = Future<String?> Function({bool forceRefresh});

/// Talks to the FastAPI backend with either a Bearer token (Google sign-in) or,
/// in dev builds only, the shared X-API-Key.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    this.apiKey = '',
    this.accessToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final AccessTokenProvider? accessToken;
  final http.Client _client;

  static const _timeout = Duration(seconds: 12);

  bool get usesApiKey => apiKey.isNotEmpty;

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool retried = false,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (usesApiKey) {
      headers['X-API-Key'] = apiKey;
    } else {
      final token = await accessToken?.call(forceRefresh: retried);
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final res = await http.Response.fromStream(await _client.send(request).timeout(_timeout));

    // Access token expired between our check and the server's: refresh once and retry.
    if (res.statusCode == 401 && !usesApiKey && !retried && accessToken != null) {
      return _send(method, path, query: query, body: body, retried: true);
    }
    return res;
  }

  static String _text(http.Response r) => utf8.decode(r.bodyBytes);

  static Map<String, dynamic> _json(http.Response r) => jsonDecode(_text(r)) as Map<String, dynamic>;

  static ApiException _error(http.Response r, String what) {
    String detail = what;
    try {
      final d = _json(r)['detail'];
      if (d is String) detail = d;
    } catch (_) {}
    return ApiException(detail, r.statusCode);
  }

  /// Raw JSON so the caller can cache it verbatim. [userId] is only used in API-key mode.
  Future<String> fetchFeedJson({String? userId}) async {
    final res = await _send('GET', '/api/v1/jobs/feed', query: {
      if (usesApiKey && userId != null) 'user_id': userId,
    });
    if (res.statusCode != 200) throw _error(res, 'Feed request failed');
    final body = _text(res);
    jsonDecode(body); // validate before it is cached
    return body;
  }

  // --- Profile ------------------------------------------------------------------

  /// Signed-in user's profile; null if not created yet.
  Future<Map<String, dynamic>?> getMyProfile() async {
    final res = await _send('GET', '/api/v1/users/me/profile');
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw _error(res, 'Could not load your profile');
    return _json(res);
  }

  Future<Map<String, dynamic>> saveMyProfile(Map<String, Object?> profile) async {
    final res = await _send('PUT', '/api/v1/users/me/profile', body: profile);
    if (res.statusCode != 200) throw _error(res, 'Could not save your profile');
    return _json(res);
  }

  /// Dev API-key mode: profiles are addressed by id.
  Future<Map<String, dynamic>?> getProfileById(String id) async {
    final res = await _send('GET', '/api/v1/users/$id');
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw _error(res, 'Could not load the profile');
    return _json(res);
  }

  Future<Map<String, dynamic>> createProfile(Map<String, Object?> profile) async {
    final res = await _send('POST', '/api/v1/users', body: profile);
    if (res.statusCode != 201) throw _error(res, 'Could not save the profile');
    return _json(res);
  }

  // --- Tracked applications (Phase 2: the server's exam watcher) --------------------

  /// Every exam the user tracks, with the watcher's status, notices and timeline.
  Future<List<Map<String, dynamic>>> listApplications() async {
    final res = await _send('GET', '/api/v1/applications');
    if (res.statusCode != 200) throw _error(res, 'Could not load tracked exams');
    return [for (final a in jsonDecode(_text(res)) as List<dynamic>) a as Map<String, dynamic>];
  }

  /// Track an exam that isn't in the feed; the watcher follows [portalUrl].
  Future<Map<String, dynamic>> addManualApplication({required String examName, String? portalUrl}) async {
    final res = await _send('POST', '/api/v1/applications', body: {
      'exam_name': examName,
      if (portalUrl != null && portalUrl.isNotEmpty) 'official_portal_url': portalUrl,
    });
    if (res.statusCode != 201) throw _error(res, 'Could not add the exam');
    return _json(res);
  }

  // --- Application status (stops deadline pings, starts the exam watcher) ----------

  Future<void> setApplicationStatus(String postDetailId, String status) async {
    final res = await _send('PUT', '/api/v1/applications/$postDetailId', body: {'status': status});
    if (res.statusCode != 204) throw _error(res, 'Could not sync application');
  }

  Future<void> deleteApplication(String postDetailId) async {
    final res = await _send('DELETE', '/api/v1/applications/$postDetailId');
    if (res.statusCode != 204) throw _error(res, 'Could not sync application');
  }

  void close() => _client.close();
}
