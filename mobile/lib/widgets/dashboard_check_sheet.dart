import 'dart:async';


import '../domain/xp.dart';
import '../models/tracked_application.dart';
import '../providers/providers.dart';
import '../providers/xp_providers.dart';
import '../utils/system_actions.dart';
import 'app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pin_dialog.dart';

/// "Check dashboard": a quick manual look at the candidate portal. Step 1 copies
/// the Reg No and opens the login; back in the app, step 2 (copy password) is
/// the highlighted button. Then one tap tells the card what you found.
Future<void> showDashboardCheck(
  BuildContext context,
  WidgetRef ref,
  TrackedApplication app, {
  required VoidCallback onAdmitCardOut,
  required VoidCallback onExamDone,
}) async {
  if (!await ensureUnlocked(context, ref) || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _DashboardCheck(app: app, onAdmitCardOut: onAdmitCardOut, onExamDone: onExamDone),
  );
}

class _DashboardCheck extends ConsumerStatefulWidget {
  const _DashboardCheck({required this.app, required this.onAdmitCardOut, required this.onExamDone});

  final TrackedApplication app;
  final VoidCallback onAdmitCardOut;
  final VoidCallback onExamDone;

  @override
  ConsumerState<_DashboardCheck> createState() => _DashboardCheckState();
}

class _DashboardCheckState extends ConsumerState<_DashboardCheck> {
  bool _opened = false;

  TrackedApplication get app => widget.app;

  Future<void> _open(String? reg) async {
    final url = app.loginUrl;
    if (url == null) return;
    if (reg != null) await copyToClipboard(context, 'Reg No', reg);
    if (!mounted) return;
    await openExternal(context, url);
    if (!_opened) {
      final exam = xpExamKey(jobPostId: app.jobPostId, examName: app.examName);
      unawaited(ref
          .read(xpProvider.notifier)
          .award(XpAction.checkedDashboard, key: 'dash:$exam:${xpDayStamp(DateTime.now())}'));
    }
    if (mounted) setState(() => _opened = true);
  }

  Future<void> _copyPassword() async {
    final password = await ref.read(secretStoreProvider).readPassword(app.id);
    if (!mounted || password == null) return;
    await copyToClipboard(context, 'Password', password, sensitive: true);
  }

  void _found(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final vault = ref.watch(vaultEntryProvider(app.id)).dataOrNull;
    final hasPassword = ref.watch(hasPasswordProvider(app.id)).dataOrNull ?? false;
    final reg = (vault?.registrationId ?? '').isEmpty ? null : vault!.registrationId;
    final roll = (vault?.rollNumber ?? '').isEmpty ? null : vault!.rollNumber;
    final host = Uri.tryParse(app.loginUrl ?? '')?.host;

    final openButton = reg != null ? 'Copy Reg No & open login' : 'Open login';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Check your dashboard', style: text.titleLarge),
          const SizedBox(height: 4),
          Text(
            [app.postName, if (host != null && host.isNotEmpty) host].join(' · '),
            style: text.bodySmall,
          ),
          const SizedBox(height: 16),
          if (app.loginUrl == null)
            Text('No login link saved yet. Add one from ⋮ → Edit links.', style: text.bodyMedium)
          else if (_opened)
            OutlinedButton.icon(
              onPressed: () => _open(reg),
              icon: const DuoIcon(AppIcon.login, size: 18),
              label: Text('1 · $openButton'),
            )
          else
            FilledButton.icon(
              onPressed: () => _open(reg),
              icon: const DuoIcon(AppIcon.login, size: 18),
              label: Text('1 · $openButton'),
            ),
          if (hasPassword) ...[
            const SizedBox(height: 8),
            // Highlighted once the login is open: the next thing you need.
            _opened
                ? FilledButton.icon(
                    onPressed: _copyPassword,
                    icon: const DuoIcon(AppIcon.copy, size: 18),
                    label: const Text('2 · Copy password'),
                  )
                : OutlinedButton.icon(
                    onPressed: _copyPassword,
                    icon: const DuoIcon(AppIcon.copy, size: 18),
                    label: const Text('2 · Copy password'),
                  ),
          ],
          if (roll != null)
            TextButton(
              onPressed: () => copyToClipboard(context, 'Roll No', roll),
              child: Text('Copy Roll No ($roll)'),
            ),
          const SizedBox(height: 6),
          Text('Come back here after each paste. The password clears from the clipboard after 45 s.',
              style: text.bodySmall),
          const Divider(height: 28),
          Text('What did you find?', style: text.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: () => _found(widget.onAdmitCardOut), child: const Text('Admit card is out')),
              if (!app.examOver(DateTime.now()))
                OutlinedButton(onPressed: () => _found(widget.onExamDone), child: const Text('Exam is done')),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Nothing new')),
            ],
          ),
        ],
      ),
    );
  }
}
