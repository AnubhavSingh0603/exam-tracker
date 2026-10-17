import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../services/fx.dart';
import '../../theme/app_theme.dart';
import '../../utils/system_actions.dart';
import '../../widgets/app_card.dart';
import '../../widgets/common.dart';
import 'models.dart';
import 'providers.dart';

/// Private applications on a four-stop track you move along yourself.
class PrivateApplicationsScreen extends ConsumerWidget {
  const PrivateApplicationsScreen({super.key});

  Future<void> _addByHand(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(String, String, String)>(context: context, builder: (_) => const _AddDialog());
    if (result == null) return;
    final (company, title, url) = result;
    await ref
        .read(privateApplicationsProvider.notifier)
        .add(company: company, title: title, url: url.isEmpty ? null : url);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(privateApplicationsProvider);
    final list = apps.dataOrNull ?? const <PrivateApplication>[];
    final open = list.where((a) => a.stage != PrivateStage.closed).length;
    return CustomScrollView(
      slivers: [
        padSliver(
          ScreenHeader(
            title: 'Applications',
            subtitle: open == 1 ? '1 in progress' : '$open in progress',
          ),
          top: 12,
        ),
        padSliver(
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _addByHand(context, ref),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
            ),
          ),
        ),
        if (list.isEmpty && !apps.isLoading)
          padSliver(
            const MutedNote('Tap “I applied” on a role, or add one you applied to elsewhere. '
                'Move it along as you hear back.'),
            top: 8,
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          sliver: SliverList.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _ApplicationCard(app: list[i]),
          ),
        ),
      ],
    );
  }
}

class _ApplicationCard extends ConsumerWidget {
  const _ApplicationCard({required this.app});

  final PrivateApplication app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final notifier = ref.read(privateApplicationsProvider.notifier);
    final closed = app.stage == PrivateStage.closed;
    final reached = closed ? -1 : PrivateStage.track.indexOf(app.stage);
    final days = ref.watch(nowProvider).difference(app.updatedAt).inDays;

    return AppCard(
      accent: closed ? AppPalette.textMuted : (app.stage == PrivateStage.offer ? AppPalette.sage : AppPalette.periwinkle),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(app.title, style: text.titleMedium)),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) async {
                  switch (v) {
                    case 'closed':
                      await notifier.setStage(app, PrivateStage.closed);
                    case 'reopen':
                      await notifier.setStage(app, PrivateStage.applied);
                    case 'delete':
                      await notifier.delete(app.id);
                      if (context.mounted) showCalmSnack(context, 'Deleted ${app.title}');
                  }
                },
                itemBuilder: (_) => [
                  if (!closed) const PopupMenuItem(value: 'closed', child: Text('Not selected')),
                  if (closed) const PopupMenuItem(value: 'reopen', child: Text('Back to “Applied”')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          Text(
            '${app.company} · ${closed ? 'Not selected' : app.stage.label}'
            '${days <= 0 ? ' today' : ' · ${days == 1 ? '1 day' : '$days days'} ago'}',
            style: text.bodySmall,
          ),
          const SizedBox(height: 10),
          // The track: tap a stop to move there.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, stage) in PrivateStage.track.indexed)
                ChoiceChip(
                  label: Text(stage.label),
                  selected: i == reached,
                  avatar: i < reached ? Icon(Icons.check_rounded, size: 16, color: AppPalette.sage) : null,
                  onSelected: (_) {
                    Fx.tap();
                    notifier.setStage(app, stage);
                  },
                ),
            ],
          ),
          if ((app.url ?? '').isNotEmpty)
            TextButton(onPressed: () => openExternal(context, app.url), child: const Text('Open the posting')),
        ],
      ),
    );
  }
}

class _AddDialog extends StatefulWidget {
  const _AddDialog();

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  final _company = TextEditingController();
  final _title = TextEditingController();
  final _url = TextEditingController();

  @override
  void dispose() {
    _company.dispose();
    _title.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: AppPalette.surface,
        title: const Text('Add an application'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _company, decoration: const InputDecoration(labelText: 'Company')),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Role')),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Link (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (_company.text.trim().isEmpty || _title.text.trim().isEmpty) return;
              Navigator.pop(context, (_company.text.trim(), _title.text.trim(), _url.text.trim()));
            },
            child: const Text('Add'),
          ),
        ],
      );
}
