import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../providers/workspace_providers.dart';
import '../services/fx.dart';
import '../theme/app_theme.dart';
import 'one_line.dart';

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
          selectedForegroundColor: AppPalette.textPrimary,
          foregroundColor: AppPalette.textMuted,
          visualDensity: VisualDensity.compact,
        ),
        segments: const [
          ButtonSegment(value: Workspace.govt, label: OneLine('Govt')),
          ButtonSegment(value: Workspace.private, label: OneLine('Private')),
        ],
        selected: {ws.shown},
        onSelectionChanged: (s) {
          Fx.tap();
          ref.read(workspaceProvider.notifier).switchTo(s.first);
        },
      ),
    );
  }
}
