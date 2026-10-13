import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';

/// A download and the address that answered it.
class DataResponse {
  const DataResponse(this.base, this.response);

  final String base;
  final http.Response response;
}

/// The data pipeline's files live at two addresses ([Env.dataBaseUrls]). A download
/// starts with the address that answered last time and moves on when one fails: a
/// network error (an ISP blocking it) or anything but 200 / 304 (e.g. GitHub Pages
/// not switched on yet).
class DataSource {
  DataSource(this._client, {List<String>? bases}) : _bases = bases ?? Env.dataBaseUrls;

  final http.Client _client;
  final List<String> _bases;

  static const _lastGoodKey = 'data.lastGoodBase';
  static const timeout = Duration(seconds: 20);

  /// GET [file] from the first address that answers. [headers] can depend on the
  /// address: an ETag only means something to the server that issued it.
  Future<DataResponse> get(String file, {Map<String, String> Function(String base)? headers}) async {
    final prefs = await _prefs();
    final last = prefs?.getString(_lastGoodKey);
    final order = [
      if (last != null && _bases.contains(last)) last,
      ..._bases.where((b) => b != last),
    ];
    Object error = http.ClientException('$file: no data address configured');
    for (final base in order) {
      final url = Uri.parse('$base/$file');
      try {
        final res = await _client.get(url, headers: headers?.call(base)).timeout(timeout);
        if (res.statusCode == 200 || res.statusCode == 304) {
          if (base != last) await prefs?.setString(_lastGoodKey, base);
          return DataResponse(base, res);
        }
        error = http.ClientException('$file: HTTP ${res.statusCode}', url);
      } on Exception catch (e) {
        error = e; // offline, blocked, timed out: try the other address
      }
    }
    throw error;
  }

  /// Remembering the last good address is a speed-up, not a requirement.
  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }
}
