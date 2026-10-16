import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/providers.dart';
import 'data.dart';
import 'matching.dart';
import 'models.dart';

final privateJobsRepositoryProvider = Provider<PrivateJobsRepository>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return PrivateJobsRepository(client);
});

typedef PrivateFeed = ({List<PrivateJob> jobs, DateTime? generatedAt, bool fresh});

class PrivateFeedNotifier extends AsyncNotifier<PrivateFeed> {
  @override
  Future<PrivateFeed> build() => ref.read(privateJobsRepositoryProvider).load();

  Future<void> refresh() async => state = AsyncData(await ref.read(privateJobsRepositoryProvider).load());
}

final privateFeedProvider = AsyncNotifierProvider<PrivateFeedNotifier, PrivateFeed>(PrivateFeedNotifier.new);

final privateProfileStoreProvider = Provider<PrivateProfileStore>((ref) => PrivateProfileStore());

class PrivateProfileNotifier extends AsyncNotifier<PrivateProfile> {
  @override
  Future<PrivateProfile> build() => ref.read(privateProfileStoreProvider).read();

  Future<void> save(PrivateProfile profile) async {
    await ref.read(privateProfileStoreProvider).write(profile);
    state = AsyncData(profile);
  }
}

final privateProfileProvider =
    AsyncNotifierProvider<PrivateProfileNotifier, PrivateProfile>(PrivateProfileNotifier.new);

final privateApplicationsStoreProvider = FutureProvider<PrivateApplicationsStore>((ref) async {
  final store = await PrivateApplicationsStore.open();
  ref.onDispose(store.close);
  return store;
});

class PrivateApplicationsNotifier extends AsyncNotifier<List<PrivateApplication>> {
  Future<PrivateApplicationsStore> get _store => ref.read(privateApplicationsStoreProvider.future);

  @override
  Future<List<PrivateApplication>> build() async => (await ref.watch(privateApplicationsStoreProvider.future)).list();

  Future<void> _reload() async => state = AsyncData(await (await _store).list());

  Future<PrivateApplication> add({required String company, required String title, String? url, String? jobId}) async {
    final now = DateTime.now();
    final app = PrivateApplication(
      id: 'p-${now.microsecondsSinceEpoch}',
      jobId: jobId,
      company: company,
      title: title,
      url: url,
      stage: PrivateStage.applied,
      createdAt: now,
      updatedAt: now,
    );
    await (await _store).save(app);
    await _reload();
    return app;
  }

  Future<void> setStage(PrivateApplication app, PrivateStage stage) async {
    await (await _store).save(app.copyWith(stage: stage, updatedAt: DateTime.now()));
    await _reload();
  }

  Future<void> delete(String id) async {
    await (await _store).delete(id);
    await _reload();
  }
}

final privateApplicationsProvider =
    AsyncNotifierProvider<PrivateApplicationsNotifier, List<PrivateApplication>>(PrivateApplicationsNotifier.new);

/// "Not for me": hidden for good (until undone).
class DismissedPrivateJobsNotifier extends AsyncNotifier<Set<String>> {
  static const _key = 'private.dismissed';

  @override
  Future<Set<String>> build() async => {...?(await SharedPreferences.getInstance()).getStringList(_key)};

  Future<void> _set(Set<String> ids) async {
    state = AsyncData(ids);
    await (await SharedPreferences.getInstance()).setStringList(_key, ids.toList());
  }

  Future<void> dismiss(String id) => _set({...state.value ?? const {}, id});

  Future<void> undo(String id) => _set({...state.value ?? const {}}..remove(id));
}

final dismissedPrivateJobsProvider =
    AsyncNotifierProvider<DismissedPrivateJobsNotifier, Set<String>>(DismissedPrivateJobsNotifier.new);

/// The feed matched to the private profile; jobs you applied to or dismissed left out.
final rankedPrivateJobsProvider = Provider<({List<PrivateMatch> shown, List<PrivateMatch> hidden})>((ref) {
  final jobs = ref.watch(privateFeedProvider).dataOrNull?.jobs ?? const <PrivateJob>[];
  final me = ref.watch(privateProfileProvider).dataOrNull ?? const PrivateProfile();
  final applied = {
    for (final a in ref.watch(privateApplicationsProvider).dataOrNull ?? const <PrivateApplication>[])
      if (a.jobId != null) a.jobId!,
  };
  final dismissed = ref.watch(dismissedPrivateJobsProvider).dataOrNull ?? const <String>{};
  return rankPrivateJobs(jobs, me, ref.watch(nowProvider), dismissed: {...dismissed, ...applied});
});
