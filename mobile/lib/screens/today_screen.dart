import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/next_step.dart';
import '../domain/urgency.dart';
import '../models/tracked_application.dart';
import '../providers/account_providers.dart';
import '../providers/backup_providers.dart';
import '../providers/jobs_providers.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../utils/system_actions.dart';
import '../widgets/app_icons.dart';
import '../widgets/celebrate.dart';
import '../widgets/common.dart';
import '../widgets/hero_card.dart';
import '../widgets/job_card.dart';
import '../widgets/motion.dart';
import 'home_shell.dart';

/// Just today: the one next step, a glance at what's waiting, the best few jobs.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider);
    final tracked = ref.watch(trackedAppsProvider);
    final snapshot = ref.watch(feedProvider).dataOrNull;
    final account = ref.watch(accountStatusProvider);
    final step = ref.watch(nextStepProvider);
    // The hero already shows one job: don't repeat it underneath.
    final heroJob = step?.feedItem?.jobPostId;
    final top = [
      for (final r in ref.watch(topMatchesProvider))
        if (r.item.jobPostId != heroJob) r
    ];
    final allJobs = ref.watch(rankedJobsProvider).length;
    final active = ref.watch(activeAppsProvider);
    final admitCards = active.where((a) => a.displayStatus == TrackerStatus.admitCardLive).length;
    final examsSoon = active.where((a) => _examWithin(a, now, const Duration(days: 14))).length;

    final subtitle = snapshot != null && snapshot.fromCache
        ? 'Offline · job list from ${formatDue(snapshot.fetchedAt)}'
        : formatDue(now).split(',').first;

    return RefreshIndicator(
      onRefresh: () => Future.wait<Object?>([
        ref.read(feedProvider.notifier).refresh(),
        ref.read(trackedAppsProvider.notifier).checkForUpdates(force: true),
        ref.read(backupControllerProvider.notifier).syncIfDue(),
      ]),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          padSliver(ScreenHeader(title: 'Today', subtitle: subtitle), top: 12),
          padSliver(const TodayProgress(), top: 12),
          if (account == AccountStatus.needsProfile)
            padSliver(
              PromptCard(
                icon: AppIcon.profile,
                title: 'One minute to finish your profile',
                body:
                    'Date of birth, category and degree are all we need to filter jobs and count your seats.',
                action: FilledButton(
                  onPressed: () => openProfileSheet(context, ref),
                  child: const Text('Finish profile'),
                ),
              ),
              top: 16,
            ),
          padSliver(
            switch (step) {
              null when tracked.isLoading => const _HeroPlaceholder(),
              null => const CalmEmptyHero(),
              final NextStep s => HeroCard(
                  step: s,
                  now: now,
                  onPrimary: () => openExternal(context, s.actionUrl),
                  onMarkApplied:
                      s.kind == NextStepKind.apply ? () => applyToJob(context, ref, s.feedItem!) : null,
                ),
            },
            top: 16,
          ),
          padSliver(
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _GlanceChip(
                  icon: AppIcon.experience,
                  label: allJobs == 1 ? '1 job for you' : '$allJobs jobs for you',
                  onTap: () => ref.read(homeTabProvider.notifier).show(1),
                ),
                if (admitCards > 0)
                  _GlanceChip(
                    icon: AppIcon.admitCard,
                    label: admitCards == 1 ? '1 admit card out' : '$admitCards admit cards out',
                    color: AppPalette.sage,
                    onTap: () => ref.read(homeTabProvider.notifier).show(2),
                  ),
                if (examsSoon > 0)
                  _GlanceChip(
                    icon: AppIcon.examDay,
                    label: examsSoon == 1 ? '1 exam in 2 weeks' : '$examsSoon exams in 2 weeks',
                    color: AppPalette.honey,
                    onTap: () => ref.read(homeTabProvider.notifier).show(2),
                  ),
              ],
            ),
            top: 16,
          ),
          if (account != AccountStatus.needsProfile) ...[
            padSliver(const SectionTitle('Best for you'), top: 24),
            if (snapshot == null)
              padSliver(
                ref.watch(feedProvider).hasError
                    ? const MutedNote('Can’t reach the job list right now. Your exams still work offline.')
                    : const Center(
                        child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
                top: 8,
              )
            else if (top.isEmpty)
              padSliver(const MutedNote('Nothing new that fits you. Nice and quiet.'), top: 8)
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverList.separated(
                  itemCount: top.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) =>
                      SettleIn(
                    id: top[i].item.jobPostId,
                    index: i,
                    child: SwipeableJob(ranked: top[i], screenContext: context, showSwipeHint: i == 0),
                  ),
                ),
              ),
            if (allJobs > top.length + (heroJob == null ? 0 : 1))
              padSliver(
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => ref.read(homeTabProvider.notifier).show(1),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text('See all $allJobs jobs'),
                  ),
                ),
                top: 8,
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

bool _examWithin(TrackedApplication a, DateTime now, Duration window) {
  final exam = a.effectiveExamAt;
  return exam != null && exam.isAfter(now) && exam.isBefore(now.add(window));
}

class _GlanceChip extends StatelessWidget {
  const _GlanceChip({required this.icon, required this.label, required this.onTap, this.color});

  final Object icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppPalette.periwinkle;
    return ActionChip(
      avatar: glyph(icon, size: 18, color: c),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: c.withValues(alpha: 0.10),
      side: BorderSide(color: c.withValues(alpha: 0.35)),
    );
  }
}

class _HeroPlaceholder extends StatelessWidget {
  const _HeroPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
      );
}
