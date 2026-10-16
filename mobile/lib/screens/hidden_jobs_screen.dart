import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/relevance.dart';
import '../providers/jobs_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/job_card.dart';
import 'settings_screen.dart';

/// Every open job your preferences hide, each with why, so nothing is lost
/// unseen. Change a preference and the job comes back to For you.
class HiddenJobsScreen extends ConsumerWidget {
  const HiddenJobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hiddenJobsProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hidden by your preferences'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen(initialTab: SettingsTab.jobs))),
            child: const Text('Preferences'),
          ),
        ],
      ),
      body: hidden.isEmpty
          ? const Padding(padding: EdgeInsets.all(16), child: MutedNote('Nothing is hidden right now.'))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: hidden.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Text(
                    'These match your degree and age, but something else rules them out. If a reason is '
                    'wrong for you (say you do have a B.Ed), change it in Preferences.',
                    style: text.bodySmall,
                  );
                }
                final (item, reason) = hidden[i - 1];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppPalette.surfaceVariant,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(reason, style: text.labelMedium?.copyWith(color: AppPalette.textMuted)),
                    ),
                    const SizedBox(height: 6),
                    JobCard(ranked: RankedJob(item, 0, const []), screenContext: context),
                  ],
                );
              },
            ),
    );
  }
}
