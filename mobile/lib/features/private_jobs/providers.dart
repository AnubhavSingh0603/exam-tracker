import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/xp.dart';
import '../../providers/providers.dart';
import '../../providers/xp_providers.dart';
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

  /// "Reset private profile": blank again, and the saved résumé copy deleted.
  Future<void> reset() async {
    final resume = state.valueOrNull?.resumePath;
    await save(const PrivateProfile());
    if (resume != null) {
      try {
        await File(resume).delete();
      } catch (_) {
        // Already gone.
      }
    }
  }
}

/// The XP key for one private application: the posting it came from, else its
/// company and title, so deleting and adding it again can't earn twice.
String privateXpKey(PrivateApplication app) =>
    'papp:${(app.jobId ?? '${app.company}|${app.title}').trim().toLowerCase()}';

/// For an XP recount: each private application, the stage it has reached, offers.
Future<Map<String, XpEarned>> privateXpForRecount(Ref ref) async {
  final things = <String, XpEarned>{};
  for (final app in await (await ref.read(privateApplicationsStoreProvider.future)).list()) {
    final key = privateXpKey(app);
    things[key] = XpEarned(XpAction.privateApplied, XpAction.privateApplied.points, app.createdAt);
    if (app.stage == PrivateStage.offer) {
      things['offer:$key'] = XpEarned(XpAction.privateOffer, XpAction.privateOffer.points, app.updatedAt);
    } else if (app.stage == PrivateStage.screening || app.stage == PrivateStage.interview) {
      things['stage:$key:${app.stage.wire}'] =
          XpEarned(XpAction.privateProgress, XpAction.privateProgress.points, app.updatedAt);
    }
  }
  return things;
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
    unawaited(ref.read(xpProvider.notifier).award(XpAction.privateApplied, key: privateXpKey(app)));
    return app;
  }

  Future<void> setStage(PrivateApplication app, PrivateStage stage) async {
    await (await _store).save(app.copyWith(stage: stage, updatedAt: DateTime.now()));
    await _reload();
    final track = PrivateStage.track;
    final key = privateXpKey(app);
    if (stage == PrivateStage.offer) {
      unawaited(ref.read(xpProvider.notifier).award(XpAction.privateOffer, key: 'offer:$key'));
    } else if (track.contains(stage) && track.indexOf(stage) > track.indexOf(app.stage)) {
      // Once per stage: moving back and forward again earns nothing more.
      unawaited(ref.read(xpProvider.notifier).award(XpAction.privateProgress, key: 'stage:$key:${stage.wire}'));
    }
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
