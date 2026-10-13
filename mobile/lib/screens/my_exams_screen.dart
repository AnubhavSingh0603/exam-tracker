import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tracked_application.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../utils/system_actions.dart';
import '../widgets/add_exam_sheet.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/tracked_application_card.dart';

/// The stages an applied exam moves through, one tab each.
enum ExamStage {
  applied('Applied'),
  admitCard('Admit card'),
  examSoon('Exam soon'),
  results('Results'),
  archived('Archived');

  const ExamStage(this.label);
  final String label;
}

/// Where an exam sits right now. "Exam soon" = scheduled, or within 30 days.
ExamStage stageOf(TrackedApplication a, DateTime now) {
  if (a.archived) return ExamStage.archived;
  return switch (a.displayStatus) {
    TrackerStatus.answerKeyLive || TrackerStatus.resultDeclared => ExamStage.results,
    TrackerStatus.admitCardLive => ExamStage.admitCard,
    TrackerStatus.examScheduled => ExamStage.examSoon,
    TrackerStatus.applied => switch (a.effectiveExamAt) {
        final exam? when exam.isAfter(now) && exam.isBefore(now.add(const Duration(days: 30))) =>
          ExamStage.examSoon,
        _ => ExamStage.applied,
      },
  };
}

class MyExamsScreen extends ConsumerWidget {
  const MyExamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(trackedAppsProvider);
    final now = ref.watch(nowProvider);
    final byStage = {for (final s in ExamStage.values) s: <TrackedApplication>[]};
    for (final a in all.dataOrNull ?? const <TrackedApplication>[]) {
      byStage[stageOf(a, now)]!.add(a);
    }
    for (final list in byStage.values) {
      list.sort((a, b) => (a.focusDate ?? DateTime(9999)).compareTo(b.focusDate ?? DateTime(9999)));
    }
    final active = all.dataOrNull?.where((a) => !a.archived).length ?? 0;
    // Open on the most pressing stage that has something in it.
    final firstBusy = [ExamStage.admitCard, ExamStage.examSoon, ExamStage.results, ExamStage.applied]
        .firstWhere((s) => byStage[s]!.isNotEmpty, orElse: () => ExamStage.applied);

    return DefaultTabController(
      length: ExamStage.values.length,
      initialIndex: firstBusy.index,
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
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppPalette.periwinkle,
            labelColor: AppPalette.textPrimary,
            unselectedLabelColor: AppPalette.textMuted,
            dividerColor: AppPalette.outline,
            tabs: [
              for (final s in ExamStage.values)
                Tab(text: byStage[s]!.isEmpty ? s.label : '${s.label} ${byStage[s]!.length}'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final s in ExamStage.values)
                  _StageList(stage: s, apps: byStage[s]!, loading: all.isLoading, error: all.hasError),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StageList extends ConsumerWidget {
  const _StageList({required this.stage, required this.apps, required this.loading, required this.error});

  final ExamStage stage;
  final List<TrackedApplication> apps;
  final bool loading;
  final bool error;

  String get _empty => switch (stage) {
        ExamStage.applied => 'Nothing here yet. Swipe a job right after you apply, or add one yourself.',
        ExamStage.admitCard => 'No admit cards out. You’ll be notified when one appears.',
        ExamStage.examSoon => 'No exams in the next 30 days.',
        ExamStage.results => 'Answer keys and results show up here.',
        ExamStage.archived => 'Swipe an exam left to archive it once you’re done with it.',
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
          if (stage == ExamStage.applied)
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
