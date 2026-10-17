import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/relevance.dart';
import '../domain/urgency.dart';
import '../models/job_preferences.dart';
import '../providers/account_providers.dart';
import '../providers/jobs_providers.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/common.dart';
import '../widgets/job_card.dart';
import '../widgets/motion.dart';
import '../widgets/one_line.dart';
import '../widgets/pill_toggle.dart';
import 'hidden_jobs_screen.dart';

enum _View { forYou, nearMiss, notForMe }

/// Every open job you qualify for, ranked for you. Tap for details; swipe right
/// once applied, left if it's not for you.
class JobsScreen extends ConsumerStatefulWidget {
  const JobsScreen({super.key});

  @override
  ConsumerState<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends ConsumerState<JobsScreen> {
  bool _explore = false;
  _View _view = _View.forYou;
  JobSort _sort = JobSort.bestMatch;
  String _query = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(RankedJob r) {
    if (_query.isEmpty) return true;
    final i = r.item;
    final hay = '${i.organization} ${i.examName} ${i.bestPost.postName} ${i.job?.advertisementNo ?? ''}'
        .toLowerCase();
    return _query.toLowerCase().split(RegExp(r'\s+')).every(hay.contains);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(jobPreferencesProvider).dataOrNull ?? JobPreferences.defaults;
    final affinity = ref.watch(affinityProvider);
    final level = ref.watch(profileProvider).dataOrNull?.qualificationTier;
    final category = ref.watch(jobsCategoryFilterProvider);
    final feed = ref.watch(feedProvider);
    final hiddenByPrefs = ref.watch(hiddenJobCountProvider);
    final rejected = ref.watch(rejectedJobsProvider);

    final source = _view == _View.nearMiss ? ref.watch(nearMissJobsProvider) : ref.watch(openJobsProvider);
    final ranked = rankJobs(source, prefs, affinity, myLevel: level, sort: _sort).where(_matches).toList();
    final counts = <JobCategory, int>{};
    for (final r in ranked) {
      final c = JobCategory.fromWire(r.item.category);
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final shown = category == null
        ? ranked
        : [
            for (final r in ranked)
              if (JobCategory.fromWire(r.item.category) == category) r
          ];
    final nearMissCount = ref.watch(rankedNearMissProvider).length;
    final forYouCount = ref.watch(rankedJobsProvider).length;

    return RefreshIndicator(
      onRefresh: () => ref.read(feedProvider.notifier).refresh(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          padSliver(
            ScreenHeader(
              title: 'Jobs',
              subtitle: forYouCount == 1 ? '1 open job fits you' : '$forYouCount open jobs fit you',
            ),
            top: 12,
          ),
          padSliver(
            Align(
              alignment: Alignment.centerLeft,
              child: PillToggle<bool>(
                options: const [(false, 'For you'), (true, 'Explore')],
                selected: _explore,
                onChanged: (v) => setState(() => _explore = v),
              ),
            ),
            top: 10,
          ),
          padSliver(
            TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim()),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search: RRB NTPC, SBI, clerk…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
                isDense: true,
              ),
            ),
            top: 14,
          ),
          if (_explore)
            ..._exploreTiles(context, ranked)
          else ...[
          padSliver(
            SegmentedButton<_View>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppPalette.surfaceVariant,
                selectedForegroundColor: AppPalette.textPrimary,
                foregroundColor: AppPalette.textMuted,
                side: BorderSide(color: AppPalette.outline),
                visualDensity: VisualDensity.compact,
              ),
              segments: [
                ButtonSegment(value: _View.forYou, label: CountLabel('For you', forYouCount)),
                ButtonSegment(value: _View.nearMiss, label: CountLabel('Near', nearMissCount)),
                ButtonSegment(value: _View.notForMe, label: CountLabel('Hidden', rejected.length)),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
            top: 12,
          ),
          if (_view == _View.notForMe)
            ..._notForMe(context, rejected)
          else ...[
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  children: [
                    _FilterChip(
                      label: 'All (${ranked.length})',
                      selected: category == null,
                      onTap: () => ref.read(jobsCategoryFilterProvider.notifier).show(null),
                    ),
                    for (final c in JobCategory.values)
                      if ((counts[c] ?? 0) > 0)
                        _FilterChip(
                          label: '${c.label} (${counts[c]})',
                          selected: category == c,
                          color: categoryColor(c),
                          onTap: () =>
                              ref.read(jobsCategoryFilterProvider.notifier).show(category == c ? null : c),
                        ),
                  ],
                ),
              ),
            ),
            padSliver(
              Row(
                children: [
                  Expanded(
                    child: hiddenByPrefs > 0 && _view == _View.forYou
                        ? InkWell(
                            onTap: () => Navigator.of(context)
                                .push(MaterialPageRoute<void>(builder: (_) => const HiddenJobsScreen())),
                            child: Text('$hiddenByPrefs hidden by your preferences ›',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppPalette.periwinkle)),
                          )
                        : const SizedBox.shrink(),
                  ),
                  PopupMenuButton<JobSort>(
                    tooltip: 'Sort',
                    initialValue: _sort,
                    onSelected: (s) => setState(() => _sort = s),
                    itemBuilder: (_) =>
                        [for (final s in JobSort.values) PopupMenuItem(value: s, child: Text(s.label))],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sort_rounded, size: 18, color: AppPalette.textMuted),
                          const SizedBox(width: 6),
                          Text(_sort.label, style: Theme.of(context).textTheme.labelLarge),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              top: 6,
            ),
            if (feed.dataOrNull == null)
              padSliver(
                feed.hasError
                    ? const MutedNote('Can’t reach the job list right now. Pull down to try again.')
                    : const Center(
                        child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
                top: 8,
              )
            else if (shown.isEmpty)
              padSliver(
                MutedNote(switch (_view) {
                  _ when _query.isNotEmpty => 'Nothing matches “$_query”.',
                  _View.nearMiss =>
                    'No near-misses right now. They appear when a job needs a little more experience than you have.',
                  _ => 'No open jobs here right now.',
                }),
                top: 8,
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                sliver: SliverList.separated(
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) =>
                      SettleIn(
                    id: shown[i].item.jobPostId,
                    index: i,
                    child: SwipeableJob(ranked: shown[i], screenContext: context, showSwipeHint: i == 0),
                  ),
                ),
              ),
          ],
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }

  /// Explore: every kind of job with how many are open; tap one to see them.
  List<Widget> _exploreTiles(BuildContext context, List<RankedJob> ranked) {
    final text = Theme.of(context).textTheme;
    final counts = <JobCategory, int>{};
    for (final r in ranked) {
      final c = JobCategory.fromWire(r.item.category);
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final kinds = [for (final c in JobCategory.values) if ((counts[c] ?? 0) > 0) c];
    if (kinds.isEmpty) {
      return [padSliver(const MutedNote('No open jobs to browse right now.'), top: 16)];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        sliver: SliverGrid.count(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.25,
          children: [
            for (final c in kinds)
              AppCard(
                onTap: () {
                  ref.read(jobsCategoryFilterProvider.notifier).show(c);
                  setState(() {
                    _explore = false;
                    _view = _View.forYou;
                  });
                },
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: categoryColor(c).withValues(alpha: AppPalette.current.isLight ? 0.13 : 0.2),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(_categoryIcon(c), size: 22, color: categoryColor(c)),
                    ),
                    const Spacer(),
                    Text(c.label, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${counts[c]} open', style: text.labelSmall),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _notForMe(BuildContext context, List<JobDecision> rejected) {
    final text = Theme.of(context).textTheme;
    if (rejected.isEmpty) {
      return [
        padSliver(const MutedNote('Jobs you swipe left go here, in case you change your mind.'), top: 16)
      ];
    }
    return [
      padSliver(const MutedNote('Bring one back and it returns to your list.'), top: 14),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        sliver: SliverList.separated(
          itemCount: rejected.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: AppPalette.outline),
          itemBuilder: (_, i) {
            final d = rejected[i];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(d.title, style: text.titleSmall),
              subtitle: Text(
                [d.organization, if (d.deadline != null) 'Last date ${formatDue(d.deadline!)}'].join(' · '),
                style: text.bodySmall,
              ),
              trailing: TextButton(
                onPressed: () => ref.read(decisionsProvider.notifier).undo(d.jobPostId),
                child: const Text('Bring back'),
              ),
            );
          },
        ),
      ),
    ];
  }
}

IconData _categoryIcon(JobCategory c) => switch (c) {
      JobCategory.railway => Icons.train_rounded,
      JobCategory.bank => Icons.account_balance_rounded,
      JobCategory.ssc => Icons.badge_rounded,
      JobCategory.upsc => Icons.workspace_premium_rounded,
      JobCategory.psu => Icons.factory_rounded,
      JobCategory.research => Icons.science_rounded,
      JobCategory.defence => Icons.shield_rounded,
      JobCategory.state => Icons.location_city_rounded,
      JobCategory.teaching => Icons.school_rounded,
      JobCategory.medical => Icons.local_hospital_rounded,
      JobCategory.court => Icons.gavel_rounded,
      JobCategory.other => Icons.work_outline_rounded,
    };

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap, this.color});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppPalette.periwinkle;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: c.withValues(alpha: 0.22),
        side: BorderSide(color: selected ? c : AppPalette.outline),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
