import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../providers/workspace_providers.dart';
import '../theme/app_theme.dart';

/// [ Govt exams | Private jobs ]: one tap swaps the whole app. Nothing at all while
/// the Private workspace is switched off.
class WorkspaceSwitch extends ConsumerWidget {
  const WorkspaceSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(workspaceProvider);
    if (!Env.privateJobsAvailable || !ws.privateEnabled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SegmentedButton<Workspace>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: AppPalette.periwinkle.withValues(alpha: 0.18),
          visualDensity: VisualDensity.compact,
        ),
        segments: const [
          ButtonSegment(value: Workspace.govt, label: Text('Govt exams')),
          ButtonSegment(value: Workspace.private, label: Text('Private jobs')),
        ],
        selected: {ws.shown},
        onSelectionChanged: (s) => ref.read(workspaceProvider.notifier).switchTo(s.first),
      ),
    );
  }
}
