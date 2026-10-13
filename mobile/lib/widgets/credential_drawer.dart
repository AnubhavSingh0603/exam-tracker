import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tracked_application.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../utils/system_actions.dart';
import 'application_tracker_sheet.dart';

/// Expanded content of a tracked card: tap-to-copy chips + portal deep link.
/// Everything is read from local storage, so it works offline.
class CredentialDrawer extends ConsumerWidget {
  const CredentialDrawer({super.key, required this.app});

  final TrackedApplication app;

  Future<void> _copyPassword(BuildContext context, WidgetRef ref) async {
    final password = await ref.read(secretStoreProvider).readPassword(app.id);
    if (!context.mounted) return;
    if (password == null || password.isEmpty) {
      showCalmSnack(context, 'No password saved yet.');
      return;
    }
    await copyToClipboard(context, 'Password', password, sensitive: true);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final input = await showApplicationTrackerSheet(
      context,
      title: 'Credentials · ${app.postName}',
      initial: ref.read(vaultEntryProvider(app.id)).dataOrNull,
      hasSavedPassword: ref.read(hasPasswordProvider(app.id)).dataOrNull ?? false,
    );
    if (input == null) return;
    await ref.read(trackedAppsProvider.notifier).saveCredentials(app.id, input);
    if (context.mounted) showCalmSnack(context, 'Credentials saved on this phone.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(vaultEntryProvider(app.id)).dataOrNull;
    final hasPassword = ref.watch(hasPasswordProvider(app.id)).dataOrNull ?? false;
    final reg = vault?.registrationId;
    final roll = vault?.rollNumber;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CopyChip(
              label: 'Reg No.',
              value: reg,
              onTap: reg == null ? null : () => copyToClipboard(context, 'Registration ID', reg),
            ),
            _CopyChip(
              label: 'Roll No.',
              value: roll,
              onTap: roll == null ? null : () => copyToClipboard(context, 'Roll number', roll),
            ),
            _CopyChip(
              label: 'Password',
              value: hasPassword ? '••••••' : null,
              onTap: hasPassword ? () => _copyPassword(context, ref) : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => openExternal(context, app.actionUrl),
                icon: const Icon(Icons.login_rounded, size: 18),
                label:
                    Text(app.status == ApplicationStatus.admitCardLive ? 'Admit card' : 'Application login'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Edit credentials',
              onPressed: () => _edit(context, ref),
              icon: const Icon(Icons.edit_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

class _CopyChip extends StatelessWidget {
  const _CopyChip({required this.label, required this.value, required this.onTap});

  final String label;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final empty = value == null;
    return Semantics(
      button: !empty,
      label: empty ? '$label not saved' : 'Copy $label',
      excludeSemantics: true,
      child: Material(
        color: AppPalette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadii.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.control),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: text.labelSmall),
                      Text(value ?? 'Not saved',
                          style: text.labelLarge?.copyWith(color: empty ? AppPalette.textMuted : null)),
                    ],
                  ),
                  if (!empty) ...[
                    const SizedBox(width: 10),
                    Icon(Icons.copy_rounded, size: 16, color: AppPalette.textMuted),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
