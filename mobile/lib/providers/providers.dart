import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/feed_builder.dart';
import '../domain/next_step.dart';
import '../models/feed.dart';
import '../models/tracked_application.dart';
import '../models/vault_entry.dart';
import '../services/background_watch.dart';
import '../services/backup_service.dart';
import '../services/calendar_sync_service.dart';
import '../services/database_service.dart';
import '../services/jobs_repository.dart';
import '../services/secret_store.dart';
import '../services/update_service.dart';
import 'account_providers.dart';
import 'backup_providers.dart';
import 'jobs_providers.dart';

// -----------------------------------------------------------------------------
// Infrastructure
// -----------------------------------------------------------------------------

/// Opened in main() before runApp and injected via ProviderScope.overrides.
final databaseProvider = Provider<DatabaseService>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden in main()'),
);

final secretStoreProvider = Provider<SecretStore>((ref) => SecretStore());

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

  /// Every change below ends with this: the Drive backup follows ~10 s later.
  void _changed() => ref.read(backupControllerProvider.notifier).markDirty();

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
      applyUrl: item.applyUrl,
      category: category,
      totalSeats: post.totalReachableSeats,
      urSeats: post.urOpenSeats,
      quotaSeats: post.categoryQuotaSeats,
      createdAt: now,
      updatedAt: now,
      jobPostId: item.jobPostId,
    );
    await _db.upsertApplication(app);
    await ref.read(decisionsProvider.notifier).record(item, applied: true); // learns what you like
    final timeline = item.timelineJson;
    if (timeline != null) await _db.saveTimeline(item.jobPostId, jsonEncode(timeline));
    await reload();
    _changed();
    return app;
  }

  /// Track an exam applied to outside the feed. The phone's exam watcher follows
  /// [portalUrl] (if given) and the job-site notices that name the exam.
  Future<TrackedApplication> addManual({required String examName, String? portalUrl}) async {
    final now = DateTime.now();
    final app = TrackedApplication(
      id: 'local-${now.microsecondsSinceEpoch}',
      examName: examName,
      postName: examName,
      status: ApplicationStatus.applied,
      portalUrl: portalUrl,
      createdAt: now,
      updatedAt: now,
    );
    await _db.upsertApplication(app);
    await reload();
    _changed();
    unawaited(checkForUpdates(force: true)); // its admit card may already be out
    return app;
  }

  /// Runs the exam watcher now (pull-to-refresh, app start). Throttled to once per
  /// 30 minutes unless [force]d; the background task runs it every ~4 hours.
  Future<int> checkForUpdates({bool force = false}) async {
    try {
      final found = await runWatchAndNotify(_db, force: force);
      if (found > 0) {
        await reload();
        _changed();
      }
      return found;
    } catch (_) {
      return 0; // offline: the next run catches up
    }
  }

  /// Delete, and the Undo for swipe-right: forget the exam entirely, with its
  /// calendar events, saved IDs and password, here and in the backup. A job
  /// that is still open returns to the feed.
  Future<void> untrack(String id) async {
    try {
      await ref.read(calendarSyncProvider).removeFromCalendar(id);
    } catch (_) {
      // Calendar permission revoked etc. — still untrack locally.
    }
    await _db.deleteApplication(id);
    await _secrets.deletePassword(id);
    await BackupPrefs.addTombstone(id, DateTime.now()); // so the backup forgets it too
    await reload();
    _changed();
  }

  Future<void> saveCredentials(String appId, CredentialsInput input) async {
    await _db.upsertVault(input.toEntry(appId));
    if (input.password.isNotEmpty) await _secrets.writePassword(appId, input.password);
    ref
      ..invalidate(vaultEntryProvider(appId))
      ..invalidate(hasPasswordProvider(appId));
    _changed();
  }

  Future<void> setStatus(String id, ApplicationStatus status,
      {DateTime? examAt, String? admitCardUrl}) async {
    await _db.updateStatus(id, status, examAt: examAt, admitCardUrl: admitCardUrl);
    await reload();
    _changed();
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
    _changed();
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

// -----------------------------------------------------------------------------
// One Next Step
// -----------------------------------------------------------------------------

/// The most urgent of what you track and the best few jobs for you.
final nextStepProvider = Provider<NextStep?>((ref) => computeNextStep(
      tracked: ref.watch(activeAppsProvider),
      feed: [for (final r in ref.watch(rankedJobsProvider).take(5)) r.item],
      now: ref.watch(nowProvider),
    ));
