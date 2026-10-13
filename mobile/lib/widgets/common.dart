import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/account_providers.dart';
import '../providers/backup_providers.dart';
import '../providers/providers.dart';
import '../screens/settings_screen.dart';
import '../theme/app_theme.dart';

/// A sliver with the screen's side gutter.
Widget padSliver(Widget child, {double top = 0}) => SliverPadding(
      padding: EdgeInsets.fromLTRB(16, top, 16, 0),
      sliver: SliverToBoxAdapter(child: child),
    );

class MutedNote extends StatelessWidget {
  const MutedNote(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) =>
      Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppPalette.textMuted));
}

/// Big screen title with the account button on the right.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text(title, style: text.headlineSmall)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: text.bodySmall),
              ],
            ],
          ),
        ),
        const AccountAvatarButton(),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.count, this.trailing});

  final String title;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      child: Row(
        children: [
          Text(title, style: text.titleMedium),
          if (count != null && count! > 0) ...[
            const SizedBox(width: 8),
            Text('$count', style: text.titleMedium?.copyWith(color: AppPalette.textMuted)),
          ],
          if (trailing != null) ...[const Spacer(), trailing!],
        ],
      ),
    );
  }
}

/// The account avatar: opens Account & settings. A dot when the backup needs a tap.
class AccountAvatarButton extends ConsumerWidget {
  const AccountAvatarButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(googleAccountProvider).dataOrNull;
    final backup = ref.watch(backupControllerProvider);
    final attention = backup.phase == BackupPhase.needsPermission || backup.phase == BackupPhase.error;
    final text = Theme.of(context).textTheme;
    return IconButton(
      tooltip: 'Account and settings',
      onPressed: () =>
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
      icon: Badge(
        isLabelVisible: attention,
        smallSize: 9,
        backgroundColor: AppPalette.honey,
        child: CircleAvatar(
          radius: 18,
          backgroundColor: AppPalette.surfaceVariant,
          child: user != null
              ? Text(user.initial, style: text.labelLarge?.copyWith(color: AppPalette.periwinkle))
              : const Icon(Icons.person_outline_rounded, size: 20, color: AppPalette.periwinkle),
        ),
      ),
    );
  }
}

class SwipeBackground extends StatelessWidget {
  const SwipeBackground({
    super.key,
    required this.color,
    required this.icon,
    required this.label,
    this.alignEnd = false,
  });

  final Color color;
  final IconData icon;
  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final children = [
      Icon(icon, color: color),
      const SizedBox(width: 8),
      Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color)),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignEnd ? children.reversed.toList() : children,
      ),
    );
  }
}

/// A calm call-to-action card (finish your profile, sign in, …).
class PromptCard extends StatelessWidget {
  const PromptCard(
      {super.key, required this.icon, required this.title, required this.body, required this.action});

  final IconData icon;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final info = context.urgencyColors.info;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: info.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: info),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: text.titleMedium)),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: text.bodyMedium?.copyWith(color: AppPalette.textMuted)),
          const SizedBox(height: 14),
          action,
        ],
      ),
    );
  }
}

/// Shows [child] (null = folded), animating the height. With "Remove animations"
/// on, it switches instantly: AnimatedSize with a zero duration breaks mid-layout
/// and leaves the card stretched and blank.
class Fold extends StatelessWidget {
  const Fold({super.key, required this.child, this.duration = const Duration(milliseconds: 200)});

  final Widget? child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final content = child ?? const SizedBox(width: double.infinity);
    if (MediaQuery.of(context).disableAnimations) return content;
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: content,
    );
  }
}
