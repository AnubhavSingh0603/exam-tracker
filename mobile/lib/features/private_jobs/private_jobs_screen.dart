import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/system_actions.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import 'matching.dart';
import 'models.dart';
import 'private_profile_screen.dart';
import 'providers.dart';

/// Company roles that fit your skills, experience and cities, best first.
class PrivateJobsScreen extends ConsumerStatefulWidget {
  const PrivateJobsScreen({super.key});

  @override
  ConsumerState<PrivateJobsScreen> createState() => _PrivateJobsScreenState();
}

class _PrivateJobsScreenState extends ConsumerState<PrivateJobsScreen> {
  bool _showHidden = false;

  void _openProfile() =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PrivateProfileScreen()));

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final feed = ref.watch(privateFeedProvider);
    final me = ref.watch(privateProfileProvider).dataOrNull ?? const PrivateProfile();
    final ranked = ref.watch(rankedPrivateJobsProvider);
    final companies = {for (final j in feed.dataOrNull?.jobs ?? const <PrivateJob>[]) j.company}.length;

    return RefreshIndicator(
      onRefresh: () => ref.read(privateFeedProvider.notifier).refresh(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          padSliver(
            ScreenHeader(
              title: 'Private jobs',
              subtitle: feed.isLoading && !feed.hasValue
                  ? 'Loading roles…'
                  : '${ranked.shown.length} roles for you · from $companies employers’ own job boards',
            ),
            top: 12,
          ),
          if (me.isEmpty)
            padSliver(
              PromptCard(
                icon: AppIcon.profile,
                title: 'Tell us what you do',
                body: 'Your skills, experience and cities pick the roles. You can fill them in from a '
                    'LinkedIn export too. This is separate from your Govt profile.',
                action: FilledButton(onPressed: _openProfile, child: const Text('Set up private profile')),
              ),
              top: 12,
            ),
          padSliver(
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _openProfile,
                  icon: const DuoIcon(AppIcon.profile, size: 18),
                  label: const Text('Private profile'),
                ),
                OutlinedButton.icon(
                  onPressed: () => openExternal(context, linkedInSearch(me).toString()),
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Search LinkedIn too'),
                ),
              ],
            ),
            top: 12,
          ),
          if (feed.hasError && !feed.hasValue)
            padSliver(const MutedNote('Couldn’t load roles. Pull down to try again.'), top: 16)
          else if (feed.hasValue && feed.value!.jobs.isEmpty)
            padSliver(const MutedNote('No roles published yet. They update every few hours.'), top: 16),
          if (ranked.hidden.isNotEmpty)
            padSliver(
              InkWell(
                onTap: () => setState(() => _showHidden = !_showHidden),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    _showHidden
                        ? 'Hide the ${ranked.hidden.length} that don’t fit'
                        : '${ranked.hidden.length} hidden: experience, cities or field ›',
                    style: text.bodySmall?.copyWith(color: AppPalette.periwinkle),
                  ),
                ),
              ),
              top: 12,
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            sliver: SliverList.separated(
              itemCount: ranked.shown.length + (_showHidden ? ranked.hidden.length : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => i < ranked.shown.length
                  ? _PrivateJobCard(match: ranked.shown[i])
                  : _PrivateJobCard(match: ranked.hidden[i - ranked.shown.length]),
            ),
          ),
        ],
      ),
    );
  }
}

String _postedLabel(DateTime? at, DateTime now) {
  if (at == null) return '';
  final days = now.difference(at).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 30) return '$days days ago';
  return '${days ~/ 30} mo ago';
}

class _PrivateJobCard extends ConsumerWidget {
  const _PrivateJobCard({required this.match});

  final PrivateMatch match;

  Future<void> _applied(BuildContext context, WidgetRef ref) async {
    final job = match.job;
    await ref
        .read(privateApplicationsProvider.notifier)
        .add(company: job.company, title: job.title, url: job.applyUrl, jobId: job.id);
    if (context.mounted) showCalmSnack(context, 'Moved to Applications: ${job.title}');
  }

  Future<void> _notForMe(BuildContext context, WidgetRef ref) async {
    final dismissed = ref.read(dismissedPrivateJobsProvider.notifier);
    await dismissed.dismiss(match.job.id);
    if (context.mounted) {
      showCalmSnack(context, 'Hidden',
          action: SnackBarAction(label: 'Undo', onPressed: () => dismissed.undo(match.job.id)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final job = match.job;
    final now = ref.watch(nowProvider);
    final where = [
      if (job.locations.isNotEmpty) job.locations.take(2).join(' · '),
      if (job.remote) 'Remote',
    ].join(' · ');
    final sage = AppPalette.sage;

    Widget chip(String label, {Color? color}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: (color ?? AppPalette.textMuted).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label, style: text.labelSmall?.copyWith(color: color ?? AppPalette.textMuted)),
        );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (match.hiddenBecause != null) ...[
            chip(match.hiddenBecause!, color: AppPalette.honey),
            const SizedBox(height: 6),
          ],
          Text(job.title, style: text.titleMedium),
          const SizedBox(height: 2),
          Text(
            [job.company, if (where.isNotEmpty) where, _postedLabel(job.postedAt, now)].where((s) => s.isNotEmpty).join(' · '),
            style: text.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (job.experienceLabel != null) chip(job.experienceLabel!, color: AppPalette.periwinkle),
              if (job.employmentType != 'full_time') chip(job.employmentType.replaceAll('_', ' ')),
              if (job.salary != null) chip(job.salary!),
              for (final s in match.sharedSkills.take(5)) chip(s, color: sage),
            ],
          ),
          if (job.summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(job.summary, maxLines: 3, overflow: TextOverflow.ellipsis, style: text.bodySmall),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.tonalIcon(
                onPressed: job.applyUrl.isEmpty ? null : () => openExternal(context, job.applyUrl),
                icon: const DuoIcon(AppIcon.applyOnline, size: 18),
                label: const Text('Apply'),
              ),
              OutlinedButton(onPressed: () => _applied(context, ref), child: const Text('I applied')),
              TextButton(onPressed: () => _notForMe(context, ref), child: const Text('Not for me')),
            ],
          ),
        ],
      ),
    );
  }
}
