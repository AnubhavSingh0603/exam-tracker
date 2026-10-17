import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../providers/workspace_providers.dart';
import 'pill_toggle.dart';

/// [ Govt | Private ]: one tap swaps the whole app, colours included. Nothing at
/// all while the Private workspace is switched off.
class WorkspaceSwitch extends ConsumerWidget {
  const WorkspaceSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(workspaceProvider);
    if (!Env.privateJobsAvailable || !ws.privateEnabled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PillToggle<Workspace>(
        options: const [(Workspace.govt, 'Govt'), (Workspace.private, 'Private')],
        selected: ws.shown,
        onChanged: ref.read(workspaceProvider.notifier).switchTo,
      ),
    );
  }
}
