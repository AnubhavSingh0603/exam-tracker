import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/account_providers.dart';
import '../providers/backup_providers.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../theme/app_theme.dart';
import 'app_icons.dart';

/// First launch on a phone: one calm choice. Signing in restores a backup made
/// on another phone (or before a reinstall), or starts one. "Not now" keeps the
/// full app, just without a backup. Returns true when the user signed in.
Future<bool> showWelcomeSheet(BuildContext context) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _WelcomeSheet(),
    ) ??
    false;

/// Shared by the welcome sheet and the account menu: sign in, then sync once.
/// Returns a short message for the user, or null when they cancelled.
Future<String?> signInAndRestore(WidgetRef ref) async {
  await ref.read(googleAccountProvider.notifier).signIn(); // throws AuthException
  final outcome = await ref.read(backupControllerProvider.notifier).sync();
  final backup = ref.read(backupControllerProvider);
  if (outcome == null) {
    return switch (backup.phase) {
      BackupPhase.offline => 'Signed in. The backup will run when you’re back online.',
      BackupPhase.needsPermission => 'Signed in, but Google Drive access wasn’t allowed. Try “Back up now”.',
      _ => backup.accountSwitchTo != null ? null : 'Signed in.',
    };
  }
  return restoreMessage(outcome);
}

String restoreMessage(BackupOutcome outcome) {
  final exams = outcome.restoredIds.length;
  if (!outcome.hadBackup || (exams == 0 && !outcome.profileRestored)) {
    return 'Signed in. Your exams and profile are now backed up to your Google Drive.';
  }
  final parts = [
    if (exams > 0) '$exams tracked exam${exams == 1 ? '' : 's'}',
    if (outcome.profileRestored) 'your profile',
  ];
  return 'Welcome back! Restored ${parts.join(' and ')}.';
}

class _WelcomeSheet extends ConsumerStatefulWidget {
  const _WelcomeSheet();

  @override
  ConsumerState<_WelcomeSheet> createState() => _WelcomeSheetState();
}

class _WelcomeSheetState extends ConsumerState<_WelcomeSheet> {
  bool _busy = false;
  String? _error;
  String? _done;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await signInAndRestore(ref);
      if (mounted) setState(() => _done = message ?? 'Signed in.');
    } on AuthException catch (e) {
      if (mounted && !e.cancelled) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn’t sign in right now. You can try later from the menu.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final info = context.urgencyColors.info;
    final done = _done;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          glyph(done == null ? AppIcon.backupSyncing : AppIcon.backupDone, size: 40, color: info),
          const SizedBox(height: 12),
          Text(done == null ? 'Keep your exams safe' : 'All set', style: text.headlineSmall),
          const SizedBox(height: 8),
          Text(
            done ??
                'Sign in with Google to bring back your data from another phone, or to start a backup. '
                    'It lives in a hidden folder of your own Google Drive that only this app can open.',
            style: text.bodyMedium?.copyWith(color: AppPalette.textMuted),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: text.bodyMedium?.copyWith(color: AppPalette.terracotta)),
          ],
          const SizedBox(height: 20),
          if (done != null)
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Continue'))
          else ...[
            FilledButton.icon(
              onPressed: _busy ? null : _signIn,
              icon: _busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const DuoIcon(AppIcon.login, size: 18),
              label: Text(_busy ? 'Restoring…' : 'Sign in with Google'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
          ],
        ],
      ),
    );
  }
}
