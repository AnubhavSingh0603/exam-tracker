import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../config/env.dart';

/// Sends a review to the team's Google Form: no account needed, nothing opens.
class ReviewService {
  ReviewService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static Uri get endpoint => Uri.parse('https://docs.google.com/forms/d/e/${Env.reviewFormId}/formResponse');

  /// "JobSummit 0.16.0 (24) · Android 15 · samsung SM-S911B": added under the
  /// text so a problem can be matched to a version and phone.
  static Future<String> appAndPhone() async {
    final parts = <String>[];
    try {
      final info = await PackageInfo.fromPlatform();
      parts.add('JobSummit ${info.version} (${info.buildNumber})');
    } catch (_) {}
    try {
      if (Platform.isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        parts.add('Android ${a.version.release}');
        parts.add('${a.manufacturer} ${a.model}');
      }
    } catch (_) {}
    return parts.join(' · ');
  }

  /// The form fields, as Google Forms expects them.
  static Map<String, String> fields({required int stars, required String text, String email = '', String about = ''}) =>
      {
        Env.reviewRatingEntry: '$stars',
        Env.reviewTextEntry: [if (text.trim().isNotEmpty) text.trim(), if (about.isNotEmpty) '[$about]'].join('\n\n'),
        if (email.trim().isNotEmpty) Env.reviewEmailEntry: email.trim(),
      };

  /// Throws when Google doesn't take it (offline, form closed).
  Future<void> send({required int stars, required String text, String email = ''}) async {
    final about = await appAndPhone();
    final res = await _client
        .post(endpoint, body: fields(stars: stars, text: text, email: email, about: about))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw http.ClientException('HTTP ${res.statusCode}', endpoint);
  }
}
