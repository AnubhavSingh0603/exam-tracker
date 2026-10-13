import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/exam_watcher.dart';
import '../models/tracked_application.dart';
import 'data_source.dart';
import 'database_service.dart';
import 'page_links.dart';

/// New notices found for one tracked exam in one run.
@immutable
class WatchFinding {
  const WatchFinding(this.before, this.after, this.updates);

  final TrackedApplication before;
  final TrackedApplication after;
  final List<DetectedUpdate> updates;
}

/// Phase 2 watcher, run on the phone (Indian internet, so official portals that
/// block GitHub's US servers still answer):
///   1. each tracked exam's own portal link, and
///   2. notices.json — admit card / answer key / result notices GitHub collected
///      from job sites — matched to each exam by name.
/// A notice URL is recorded once per exam, so only unseen ones count as new.
class ExamWatchService {
  ExamWatchService(this._db, {http.Client? client}) : _client = client ?? http.Client();

  final DatabaseService _db;
  final http.Client _client;

  static const _timeout = Duration(seconds: 20);
  static const _maxPageBytes = 4 * 1024 * 1024;
  static const _keepUpdates = 30;
  // Results can arrive more than a year after applying; after that, stop watching.
  static const _watchWindow = Duration(days: 548);
  static const _userAgent = 'Mozilla/5.0 (Linux; Android) ExamTracker/0.5 (personal exam tracker)';

  Future<List<WatchFinding>> run({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final apps = [
      for (final a in await _db.listApplications())
        if (!a.archived &&
            a.displayStatus != TrackerStatus.resultDeclared &&
            a.createdAt.isAfter(at.subtract(_watchWindow)))
          a,
    ];
    if (apps.isEmpty) return const [];

    final notices = await _notices();
    final pages = <String, List<PageLink>?>{}; // one fetch per portal per run
    final findings = <WatchFinding>[];
    for (final app in apps) {
      final known = {for (final u in app.updates) canonicalUrl(u.url)};
      final detected = <DetectedUpdate>[];
      final portal = app.portalUrl;
      if (portal != null && portal.isNotEmpty) {
        final links = pages.containsKey(portal) ? pages[portal] : (pages[portal] = await _pageLinks(portal));
        if (links != null) {
          detected.addAll(detectUpdates(
            links,
            examName: app.examName,
            organization: app.organization,
            source: UpdateSource.official,
            examSpecificPage: isExamSpecificPage(portal),
            knownUrls: known,
          ));
        }
      }
      detected.addAll(detectUpdates(
        notices,
        examName: app.examName,
        organization: app.organization,
        source: UpdateSource.aggregator,
        examSpecificPage: false,
        knownUrls: {...known, for (final d in detected) d.url},
      ));
      if (detected.isEmpty) continue;
      findings.add(await _record(app, detected, at));
    }
    return findings;
  }

  Future<WatchFinding> _record(TrackedApplication app, List<DetectedUpdate> detected, DateTime at) async {
    final status =
        advanceStatus(app.watcherStatus ?? TrackerStatus.applied, detected.map((d) => d.milestone));
    final updates = [
      for (final d in detected)
        ExamUpdate(
          milestone: d.milestone.wire,
          title: d.title,
          url: d.url,
          eventDate: d.eventDate,
          detectedAt: at,
          source: d.source.name,
        ),
      ...app.updates,
    ].take(_keepUpdates).toList();
    var timeline = app.timelineRaw ?? <String, dynamic>{'job_post_id': app.jobPostId ?? app.id};
    for (final d in detected) {
      timeline = fillTimeline(timeline, d, at);
    }
    await _db.saveWatcherState(
      app.id,
      status: status.wire,
      updatesJson: jsonEncode([for (final u in updates) u.toJson()]),
      timelineJson: jsonEncode(timeline),
    );
    final after = await _db.getApplication(app.id) ?? app;
    return WatchFinding(app, after, detected);
  }

  Future<List<PageLink>> _notices() async {
    try {
      final res = (await DataSource(_client).get('notices.json')).response;
      if (res.statusCode != 200) return const [];
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return [
        for (final n in (data['notices'] as List<dynamic>? ?? const []))
          if (n is Map<String, dynamic> && n['url'] is String)
            PageLink(url: n['url'] as String, title: n['title'] as String? ?? ''),
      ];
    } catch (_) {
      return const []; // offline or the pipeline hasn't run yet: portals still get checked
    }
  }

  /// null when the page can't be read this time (offline, blocked, not HTML).
  Future<List<PageLink>?> _pageLinks(String url) async {
    try {
      final uri = Uri.parse(url.contains('://') ? url : 'https://$url');
      final res = await _client
          .get(uri, headers: {'User-Agent': _userAgent, 'Accept': 'text/html,*/*'}).timeout(_timeout);
      if (res.statusCode != 200 || res.bodyBytes.length > _maxPageBytes) return null;
      final type = res.headers['content-type'] ?? '';
      if (type.contains('pdf')) return const [];
      return extractPageLinks(
          utf8.decode(res.bodyBytes, allowMalformed: true), res.request?.url.toString() ?? url);
    } catch (_) {
      return null;
    }
  }

  void close() => _client.close();
}
