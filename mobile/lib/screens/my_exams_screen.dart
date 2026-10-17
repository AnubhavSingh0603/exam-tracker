import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/delivery_track.dart';
import '../domain/lifecycle.dart';
import '../models/tracked_application.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../utils/system_actions.dart';
import '../widgets/add_exam_sheet.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/progress_map.dart';
import '../widgets/tracked_application_card.dart';

/// Three tabs: everything still in progress, exams whose result is out, and the
/// ones put away.
enum ExamTab {
  tracked('Tracked'),
  resultsOut('Results out'),
  archived('Archived');

  const ExamTab(this.label);
  final String label;
}

/// Where an exam belongs: archived if put away, "Results out" once its result
/// stop is done (including a stage whose next one can be tracked), else tracked.
ExamTab tabOf(TrackedApplication a, DateTime now) {
  if (a.archived) return ExamTab.archived;
  final resultStop = buildDeliveryTrack(a, now).stops[4];
  return resultStop.state == StageState.completed ? ExamTab.resultsOut : ExamTab.tracked;
}

class MyExamsScreen extends ConsumerWidget {
  const MyExamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(trackedAppsProvider);
    final now = ref.watch(nowProvider);
    final byTab = {for (final t in ExamTab.values) t: <TrackedApplication>[]};
    for (final a in all.dataOrNull ?? const <TrackedApplication>[]) {
      byTab[tabOf(a, now)]!.add(a);
    }
    // Soonest date first; exams waiting on an answer key or result (no date) after.
    for (final list in byTab.values) {
      list.sort((a, b) =>
          (a.focusDateAt(now) ?? DateTime(9999)).compareTo(b.focusDateAt(now) ?? DateTime(9999)));
    }
    final active = all.dataOrNull?.where((a) => !a.archived).length ?? 0;

    return DefaultTabController(
      length: ExamTab.values.length,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ScreenHeader(
              title: 'My exams',
              subtitle: active == 1 ? '1 exam you applied to' : '$active exams you applied to',
            ),
          ),
          TabBar(
            indicatorColor: AppPalette.periwinkle,
            labelColor: AppPalette.textPrimary,
            unselectedLabelColor: AppPalette.textMuted,
            dividerColor: AppPalette.outline,
            tabs: [
              for (final t in ExamTab.values)
                Tab(text: byTab[t]!.isEmpty ? t.label : '${t.label} ${byTab[t]!.length}'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final t in ExamTab.values)
                  _StageList(
                    tab: t,
                    apps: byTab[t]!,
                    loading: all.isLoading,
                    error: all.hasError,
                    // The climb shows every exam not put away, finished ones at the flag.
                    mapApps: t == ExamTab.tracked ? [...byTab[ExamTab.tracked]!, ...byTab[ExamTab.resultsOut]!] : const [],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StageList extends ConsumerWidget {
  const _StageList({
    required this.tab,
    required this.apps,
    required this.loading,
    required this.error,
    this.mapApps = const [],
  });

  final List<TrackedApplication> mapApps;

  final ExamTab tab;
  final List<TrackedApplication> apps;
  final bool loading;
  final bool error;

  String get _empty => switch (tab) {
        ExamTab.tracked => 'Nothing here yet. Swipe a job right after you apply, or add one yourself.',
        ExamTab.resultsOut => 'Exams move here once their result is out.',
        ExamTab.archived => 'Swipe an exam left to archive it once you’re done with it.',
      };

  void _setArchived(BuildContext context, WidgetRef ref, TrackedApplication app, {required bool archived}) {
    final notifier = ref.read(trackedAppsProvider.notifier);
    notifier.setArchived(app.id, archived: archived);
    showCalmSnack(
      context,
      archived ? 'Archived ${app.postName}' : 'Restored ${app.postName}',
      action:
          SnackBarAction(label: 'Undo', onPressed: () => notifier.setArchived(app.id, archived: !archived)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider);
    return RefreshIndicator(
      onRefresh: () => ref.read(trackedAppsProvider.notifier).checkForUpdates(force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (mapApps.isNotEmpty) ...[
            ProgressMap(apps: mapApps, now: now),
            const SizedBox(height: 4),
          ],
          if (tab == ExamTab.tracked)
            const Align(alignment: Alignment.centerRight, child: AddExamButton()),
          if (error)
            const MutedNote('Could not read local data. Restart the app.')
          else if (apps.isEmpty && !loading)
            Padding(padding: const EdgeInsets.only(top: 8), child: MutedNote(_empty))
          else
            for (final app in apps) ...[
              Dismissible(
                key: ValueKey('tracked-${app.id}'),
                direction: DismissDirection.endToStart,
                background: const SizedBox.shrink(),
                secondaryBackground: SwipeBackground(
                  color: AppPalette.textMuted,
                  icon: app.archived ? Icons.unarchive_rounded : AppIcon.archive,
                  label: app.archived ? 'Restore' : 'Archive',
                  alignEnd: true,
                ),
                onDismissed: (_) => _setArchived(context, ref, app, archived: !app.archived),
                child: TrackedApplicationCard(app: app, now: now),
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}
