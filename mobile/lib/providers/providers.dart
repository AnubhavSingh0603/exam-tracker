import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../domain/feed_builder.dart';
import '../domain/next_step.dart';
import '../models/feed.dart';
import '../models/tracked_application.dart';
import '../models/vault_entry.dart';
import '../services/api_client.dart';
import '../services/calendar_sync_service.dart';
import '../services/database_service.dart';
import '../services/jobs_repository.dart';
import '../services/secret_store.dart';
import '../services/update_service.dart';
import 'account_providers.dart';

// -----------------------------------------------------------------------------
// Infrastructure
// -----------------------------------------------------------------------------

/// Opened in main() before runApp and injected via ProviderScope.overrides.
final databaseProvider = Provider<DatabaseService>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden in main()'),
);

final secretStoreProvider = Provider<SecretStore>((ref) => SecretStore());

final apiClientProvider = Provider<ApiClient?>((ref) {
  if (!Env.hasBackend) return null;
  final client = ApiClient(
    baseUrl: Env.apiBaseUrl,
    apiKey: Env.apiKey, // empty unless a non-prod dev build set API_KEY
    // read, not watch: the client lives across token refreshes
    accessToken: ({bool forceRefresh = false}) =>
        ref.read(authProvider.notifier).accessToken(forceRefresh: forceRefresh),
  );
  ref.onDispose(client.close);
  return client;
});

final updateServiceProvider = Provider<UpdateService>((ref) {
  final service = UpdateService();
  ref.onDispose(service.close);
  return service;
});

final calendarSyncProvider =
    Provider<CalendarSyncService>((ref) => CalendarSyncService(ref.watch(databaseProvider)));

/// Ticks once a minute so countdowns stay honest without per-widget timers.
class NowNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final timer = Timer.periodic(const Duration(minutes: 1), (_) => state = DateTime.now());
    ref.onDispose(timer.cancel);
    return DateTime.now();
  }
}

final nowProvider = NotifierProvider<NowNotifier, DateTime>(NowNotifier.new);

extension AsyncValueData<T> on AsyncValue<T> {
  /// Current data, including stale data kept during a reload; null otherwise.
  /// (Works the same on Riverpod 2.x and 3.x.)
  T? get dataOrNull => hasValue ? requireValue : null;
}

// -----------------------------------------------------------------------------
// Tracked applications (offline source of truth)
// -----------------------------------------------------------------------------

class TrackedAppsNotifier extends AsyncNotifier<List<TrackedApplication>> {
  DatabaseService get _db => ref.read(databaseProvider);
  SecretStore get _secrets => ref.read(secretStoreProvider);

  @override
  Future<List<TrackedApplication>> build() => _db.listApplications();

  Future<void> reload() async => state = AsyncData(await _db.listApplications());

  /// Swipe-right: record the application immediately, credentials come later.
  Future<TrackedApplication> markAppliedFromFeed(FeedItem item, {String? category}) async {
    final now = DateTime.now();
    final post = item.bestPost;
    final app = TrackedApplication(
      id: post.postDetailId,
      examName: item.examName,
      postName: post.postName,
      organization: item.organization,
      status: ApplicationStatus.applied,
      deadline: item.deadline,
      portalUrl: item.portalUrl,
      category: category,
      totalSeats: post.totalReachableSeats,
      urSeats: post.urOpenSeats,
      quotaSeats: post.categoryQuotaSeats,
      createdAt: now,
      updatedAt: now,
      jobPostId: item.jobPostId,
    );
    await _db.upsertApplication(app);
    final timeline = item.timelineJson;
    if (timeline != null) await _db.saveTimeline(item.jobPostId, jsonEncode(timeline));
    await reload();
    _syncStatus(app.id, ApplicationStatus.applied);
    return app;
  }

  /// Track an exam applied to outside the feed. With the backend it gets the
  /// exam watcher; offline it is a plain local reminder.
  Future<TrackedApplication> addManual({required String examName, String? portalUrl}) async {
    final now = DateTime.now();
    String id = 'local-${now.microsecondsSinceEpoch}';
    String? serverId;
    final api = _signedInApi();
    if (api != null) {
      try {
        final created = await api.addManualApplication(examName: examName, portalUrl: portalUrl);
        id = serverId = created['id'] as String;
      } on ApiException {
        rethrow; // e.g. invalid link: let the form say so
      } catch (_) {
        // Offline: keep it local; it can be re-added once online.
      }
    }
    final app = TrackedApplication(
      id: id,
      examName: examName,
      postName: examName,
      status: ApplicationStatus.applied,
      portalUrl: portalUrl,
      createdAt: now,
      updatedAt: now,
    );
    await _db.upsertApplication(app);
    if (serverId != null) {
      await _db.applyServerState(id, serverId: serverId, serverStatus: 'applied', updatesJson: '[]');
    }
    await reload();
    return app;
  }

  ApiClient? _signedInApi() {
    final api = ref.read(apiClientProvider);
    if (api == null || api.usesApiKey) return null; // dev key mode has no per-user applications
    if (ref.read(authProvider).dataOrNull == null) return null;
    return api;
  }

  /// Pulls the exam watcher's findings (status, notices, timeline) into SQLite,
  /// and updates the phone calendar where an announced exam date changed.
  /// Best-effort: offline is fine, the last synced state stays on screen.
  Future<void> syncFromServer() async {
    final api = _signedInApi();
    if (api == null) return;
    final List<Map<String, dynamic>> remote;
    try {
      remote = await api.listApplications();
    } catch (_) {
      return;
    }
    final before = {for (final a in await _db.listApplications()) a.id: a};
    final byServerId = {
      for (final a in before.values)
        if (a.serverId != null) a.serverId!: a.id
    };
    for (final r in remote) {
      final serverId = r['id'] as String;
      final postId = r['post_detail_id'] as String?;
      var localId = byServerId[serverId] ?? (postId != null && before.containsKey(postId) ? postId : null);
      if (localId == null) {
        // Tracked on another device (or before reinstalling): add it here too.
        localId = postId ?? serverId;
        final now = DateTime.now();
        await _db.upsertApplication(TrackedApplication(
          id: localId,
          examName: r['exam_name'] as String,
          postName: r['exam_name'] as String,
          organization: r['organization'] as String?,
          status: ApplicationStatus.applied,
          portalUrl: r['official_portal_url'] as String?,
          jobPostId: r['job_id'] as String?,
          createdAt: now,
          updatedAt: now,
        ));
      }
      final timeline = r['timeline'];
      await _db.applyServerState(
        localId,
        serverId: serverId,
        serverStatus: r['status'] as String? ?? 'applied',
        updatesJson: jsonEncode(r['updates'] ?? const []),
        timelineJson: timeline == null ? null : jsonEncode(timeline),
      );
    }
    await reload();

    // Keep calendar events honest when the watcher found a (new) exam date.
    final calendar = ref.read(calendarSyncProvider);
    for (final app in state.dataOrNull ?? const <TrackedApplication>[]) {
      final old = before[app.id];
      if (app.calendarSynced && old != null && old.effectiveExamAt != app.effectiveExamAt) {
        try {
          await calendar.syncExamToCalendar(app);
        } catch (_) {}
      }
    }
  }

  /// Best-effort: lets the server stop deadline pings and start admit-card matching.
  /// Local SQLite stays the source of truth, so failures (offline) are ignored.
  void _syncStatus(String postDetailId, ApplicationStatus? status) {
    final api = ref.read(apiClientProvider);
    if (api == null || api.usesApiKey) return;
    if (ref.read(authProvider).dataOrNull == null) return;
    unawaited(() async {
      try {
        if (status == null) {
          await api.deleteApplication(postDetailId);
        } else {
          await api.setApplicationStatus(postDetailId, status.wire);
        }
      } catch (_) {}
    }());
  }

  /// Undo for swipe-right: forget it entirely so it returns to the feed.
  Future<void> untrack(String id) async {
    try {
      await ref.read(calendarSyncProvider).removeFromCalendar(id);
    } catch (_) {
      // Calendar permission revoked etc. — still untrack locally.
    }
    await _db.deleteApplication(id);
    await _secrets.deletePassword(id);
    await reload();
    _syncStatus(id, null);
  }

  Future<void> saveCredentials(String appId, CredentialsInput input) async {
    await _db.upsertVault(input.toEntry(appId));
    if (input.password.isNotEmpty) await _secrets.writePassword(appId, input.password);
    ref
      ..invalidate(vaultEntryProvider(appId))
      ..invalidate(hasPasswordProvider(appId));
  }

  Future<void> setStatus(String id, ApplicationStatus status,
      {DateTime? examAt, String? admitCardUrl}) async {
    await _db.updateStatus(id, status, examAt: examAt, admitCardUrl: admitCardUrl);
    await reload();
    _syncStatus(id, status);
  }

  /// Optimistic so the Dismissible leaves the tree in the same frame.
  Future<void> setArchived(String id, {required bool archived}) async {
    final current = state.dataOrNull;
    if (current != null) {
      state = AsyncData([
        for (final a in current) a.id == id ? a.copyWith(archived: archived) : a,
      ]);
    }
    await _db.setArchived(id, archived: archived);
    await reload();
  }
}

final trackedAppsProvider =
    AsyncNotifierProvider<TrackedAppsNotifier, List<TrackedApplication>>(TrackedAppsNotifier.new);

final activeAppsProvider = Provider<List<TrackedApplication>>((ref) {
  final all = ref.watch(trackedAppsProvider).dataOrNull ?? const [];
  return [
    for (final a in all)
      if (!a.archived) a
  ];
});

final vaultEntryProvider = FutureProvider.autoDispose
    .family<VaultEntry?, String>((ref, appId) => ref.watch(databaseProvider).getVault(appId));

/// Only whether a password exists; the value itself is read on tap.
final hasPasswordProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, appId) => ref.watch(secretStoreProvider).hasPassword(appId));

// -----------------------------------------------------------------------------
// Feed (online, with last-good cache for offline start-up)
// -----------------------------------------------------------------------------

final jobsRepositoryProvider = Provider<JobsRepository>((ref) {
  final repo = JobsRepository(ref.watch(databaseProvider));
  ref.onDispose(repo.close);
  return repo;
});

/// jobs.json from the data pipeline. Starts from the offline copy when there is
/// one (instant start-up), then refreshes from the network in the background.
class JobsLoadNotifier extends AsyncNotifier<JobsLoad?> {
  JobsRepository get _repo => ref.read(jobsRepositoryProvider);

  @override
  Future<JobsLoad?> build() async {
    final cached = await _repo.cached();
    if (cached != null) {
      unawaited(Future.microtask(refresh));
      return cached;
    }
    return _repo.load();
  }

  Future<void> refresh() async {
    final next = await AsyncValue.guard(_repo.load);
    // Keep showing the last good list when a refresh fails.
    if (next.hasValue || !state.hasValue) state = next;
  }
}

final jobsLoadProvider = AsyncNotifierProvider<JobsLoadNotifier, JobsLoad?>(JobsLoadNotifier.new);

/// The personalised feed, computed on this phone from jobs.json + the profile.
class FeedNotifier extends AsyncNotifier<FeedSnapshot> {
  @override
  Future<FeedSnapshot> build() async {
    final profile = await ref.watch(profileProvider.future);
    if (profile == null || !profile.isComplete) return FeedSnapshot.empty;
    final load = await ref.watch(jobsLoadProvider.future);
    if (load == null) return FeedSnapshot.empty;
    final tracked = ref.read(trackedAppsProvider).dataOrNull ?? const <TrackedApplication>[];
    return buildFeed(
      jobs: load.file,
      profile: profile,
      appliedPostIds: {for (final a in tracked) a.id},
      now: DateTime.now(),
      fetchedAt: load.fetchedAt,
      fromCache: load.fromCache,
    );
  }

  /// Pull-to-refresh: fetch jobs.json again (the feed rebuilds from it).
  Future<void> refresh() => ref.read(jobsLoadProvider.notifier).refresh();
}

final feedProvider = AsyncNotifierProvider<FeedNotifier, FeedSnapshot>(FeedNotifier.new);

/// Paralysis Shield: unapplied, still-open items only, never more than 5.
const feedCap = 5;

final visibleFeedProvider = Provider<List<FeedItem>>((ref) {
  final snapshot = ref.watch(feedProvider).dataOrNull;
  if (snapshot == null) return const [];
  final trackedIds = {
    for (final a in ref.watch(trackedAppsProvider).dataOrNull ?? const <TrackedApplication>[]) a.id
  };
  final now = ref.watch(nowProvider);
  return [
    for (final item in snapshot.items)
      if (!trackedIds.contains(item.bestPost.postDetailId) && item.deadline.isAfter(now)) item,
  ].take(feedCap).toList(growable: false);
});

/// "💡 Suggested" tab: same Paralysis Shield rules as the main feed.
final visibleSuggestedProvider = Provider<List<FeedItem>>((ref) {
  final snapshot = ref.watch(feedProvider).dataOrNull;
  if (snapshot == null) return const [];
  final trackedIds = {
    for (final a in ref.watch(trackedAppsProvider).dataOrNull ?? const <TrackedApplication>[]) a.id
  };
  final now = ref.watch(nowProvider);
  return [
    for (final item in snapshot.suggested)
      if (!trackedIds.contains(item.bestPost.postDetailId) && item.deadline.isAfter(now)) item,
  ].take(feedCap).toList(growable: false);
});

// -----------------------------------------------------------------------------
// One Next Step
// -----------------------------------------------------------------------------

final nextStepProvider = Provider<NextStep?>((ref) => computeNextStep(
      tracked: ref.watch(activeAppsProvider),
      feed: ref.watch(visibleFeedProvider),
      now: ref.watch(nowProvider),
    ));
