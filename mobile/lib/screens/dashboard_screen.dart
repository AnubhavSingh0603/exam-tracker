import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';
import '../domain/next_step.dart';
import '../domain/urgency.dart';
import '../models/feed.dart';
import '../models/tracked_application.dart';
import '../providers/account_providers.dart';
import '../providers/providers.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/system_actions.dart';
import '../widgets/add_exam_sheet.dart';
import '../widgets/application_tracker_sheet.dart';
import '../widgets/hero_card.dart';
import '../widgets/tracked_application_card.dart';
import 'feed_screen.dart';
import 'profile_setup_screen.dart';

/// Single bounded screen: hero → ≤5 new jobs (direct / 💡 suggested) → tracked
/// applications. No infinite scroll, no navigation away from "today".
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Records the application, then (non-blocking) offers Undo and the
  /// Application Tracker sheet for credentials.
  Future<TrackedApplication> _markApplied(WidgetRef ref, FeedItem item, String? category) async {
    final app = await ref.read(trackedAppsProvider.notifier).markAppliedFromFeed(item, category: category);
    unawaited(HapticFeedback.mediumImpact());
    return app;
  }

  Future<void> _afterApplied(BuildContext context, WidgetRef ref, TrackedApplication app) async {
    if (!context.mounted) return;
    final notifier = ref.read(trackedAppsProvider.notifier);
    showCalmSnack(
      context,
      'Marked as applied ✓',
      action: SnackBarAction(label: 'Undo', onPressed: () => notifier.untrack(app.id)),
    );
    final creds = await showApplicationTrackerSheet(context, title: 'Applied · ${app.postName}');
    if (creds != null) await notifier.saveCredentials(app.id, creds);
  }

  void _archive(BuildContext context, WidgetRef ref, TrackedApplication app) {
    final notifier = ref.read(trackedAppsProvider.notifier);
    unawaited(notifier.setArchived(app.id, archived: true));
    showCalmSnack(
      context,
      'Archived ${app.postName}',
      action: SnackBarAction(label: 'Undo', onPressed: () => notifier.setArchived(app.id, archived: false)),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider);
    final trackedAsync = ref.watch(trackedAppsProvider);
    final feedAsync = ref.watch(feedProvider);
    final step = ref.watch(nextStepProvider);
    final active = ref.watch(activeAppsProvider);
    final snapshot = feedAsync.dataOrNull;
    final category = snapshot?.category;

    // The hero already shows one feed item; don't repeat it below.
    final heroPostId = step?.feedItem?.bestPost.postDetailId;

    final account = ref.watch(accountStatusProvider);

    return _AccountGate(
      child: Scaffold(
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () => ref.read(feedProvider.notifier).refresh(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                _pad(_Header(snapshot: snapshot, now: now, trailing: const _AccountButton()), top: 20),
                _pad(
                  switch (step) {
                    null when trackedAsync.isLoading => const _HeroPlaceholder(),
                    null => const CalmEmptyHero(),
                    final NextStep s => HeroCard(
                        step: s,
                        now: now,
                        onPrimary: () => openExternal(context, s.actionUrl),
                        onMarkApplied: s.kind == NextStepKind.apply
                            ? () async {
                                final app = await _markApplied(ref, s.feedItem!, category);
                                if (context.mounted) await _afterApplied(context, ref, app);
                              }
                            : null,
                      ),
                  },
                  top: 16,
                ),
                if (account != AccountStatus.offline) ...[
                  _pad(const _SectionTitle('New for you'), top: 28),
                  ...switch (account) {
                    AccountStatus.signedOut => [_pad(const _SignInCard(), top: 12)],
                    AccountStatus.needsProfile => [_pad(const _FinishProfileCard(), top: 12)],
                    AccountStatus.loading when snapshot == null => [
                        _pad(
                            const Center(
                                child:
                                    Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
                            top: 8),
                      ],
                    _ => [
                        SplitFeedSection(
                          excludePostId: heroPostId,
                          markApplied: (item) => _markApplied(ref, item, category),
                          afterApplied: (app) => unawaited(_afterApplied(context, ref, app)),
                        ),
                      ],
                  },
                ],
                _pad(
                  _SectionTitle('Tracking', count: active.length, trailing: const AddExamButton()),
                  top: 20,
                ),
                if (trackedAsync.hasError)
                  _pad(const MutedNote('Could not read local data. Restart the app.'), top: 8)
                else if (active.isEmpty && !trackedAsync.isLoading)
                  _pad(const MutedNote('Nothing tracked yet. Swipe a job right after you apply.'), top: 8)
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    sliver: SliverList.separated(
                      itemCount: active.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final app = active[i];
                        return Dismissible(
                          key: ValueKey('tracked-${app.id}'),
                          direction: DismissDirection.endToStart,
                          background: const SizedBox.shrink(),
                          secondaryBackground: const SwipeBackground(
                            color: AppPalette.textMuted,
                            icon: Icons.archive_rounded,
                            label: 'Archive',
                            alignEnd: true,
                          ),
                          onDismissed: (_) => _archive(context, ref, app),
                          child: TrackedApplicationCard(app: app, now: now),
                        );
                      },
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 48)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _pad(Widget child, {double top = 0}) => SliverPadding(
      padding: EdgeInsets.fromLTRB(16, top, 16, 0),
      sliver: SliverToBoxAdapter(child: child),
    );

class _Header extends StatelessWidget {
  const _Header({required this.snapshot, required this.now, this.trailing});

  final FeedSnapshot? snapshot;
  final DateTime now;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final snap = snapshot;
    final String status;
    if (snap != null && snap.fromCache) {
      status = 'Offline · job list from ${formatDue(snap.fetchedAt)}';
    } else {
      status = formatDue(now).split(',').first; // "Sat 11 Oct"
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Today', style: text.headlineSmall),
              const SizedBox(height: 2),
              Text(status, style: text.bodySmall),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.count, this.trailing});

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

class _HeroPlaceholder extends StatelessWidget {
  const _HeroPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
      );
}

// -----------------------------------------------------------------------------
// Account: sign-in, profile prompt, notification permission
// -----------------------------------------------------------------------------

Future<void> _signIn(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(authProvider.notifier).signIn();
  } on AuthException catch (e) {
    if (!e.cancelled && context.mounted) showCalmSnack(context, e.message);
  } catch (_) {
    if (context.mounted) showCalmSnack(context, 'Couldn’t reach the server. Try again in a moment.');
  }
}

Future<void> _openProfile(BuildContext context, WidgetRef ref) => showProfileSetupSheet(
      context,
      initial: ref.read(profileProvider).dataOrNull,
      suggestedName: ref.read(authProvider).dataOrNull?.name,
    );

/// Opens the profile sheet once per app session when it's missing, and asks for
/// notification permission once (Android 13+). Never blocks the dashboard.
class _AccountGate extends ConsumerStatefulWidget {
  const _AccountGate({required this.child});

  final Widget child;

  @override
  ConsumerState<_AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends ConsumerState<_AccountGate> {
  bool _promptedThisSession = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<AccountStatus>(accountStatusProvider, (_, status) {
      if (status == AccountStatus.needsProfile && !_promptedThisSession) {
        _promptedThisSession = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openProfile(context, ref);
        });
      }
    }, fireImmediately: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _askNotificationsOnce());
  }

  /// FCM pings need this on Android 13+. Asked once; the system dialog is the explanation.
  Future<void> _askNotificationsOnce() async {
    const key = 'perm.notificationsAsked';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(key) ?? false) return;
      await prefs.setBool(key, true);
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {
      // Unsupported platform or plugin missing: notifications are optional.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AccountButton extends ConsumerWidget {
  const _AccountButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(accountStatusProvider);
    if (status == AccountStatus.offline) return const SizedBox.shrink();
    if (status == AccountStatus.signedOut) {
      return TextButton.icon(
        onPressed: () => _signIn(context, ref),
        icon: const Icon(Icons.login_rounded, size: 18),
        label: const Text('Sign in'),
      );
    }
    final session = ref.watch(authProvider).dataOrNull;
    final who = [session?.name, session?.email].whereType<String>().map((s) => s.trim()).firstWhere(
          (s) => s.isNotEmpty,
          orElse: () => 'D',
        );
    final initial = who.characters.first.toUpperCase();
    return PopupMenuButton<String>(
      tooltip: 'Account',
      onSelected: (v) async {
        if (v == 'profile') await _openProfile(context, ref);
        if (v == 'signout') await ref.read(authProvider.notifier).signOut();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'profile', child: Text('Edit profile')),
        if (session != null) const PopupMenuItem(value: 'signout', child: Text('Sign out')),
      ],
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: AppPalette.surfaceVariant,
          child: Text(Env.devKeyMode ? 'D' : initial,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppPalette.periwinkle)),
        ),
      ),
    );
  }
}

class _SignInCard extends ConsumerWidget {
  const _SignInCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return _PromptCard(
      icon: Icons.person_search_rounded,
      title: 'See jobs you can actually apply for',
      body: 'Sign in so we can match notifications to your age, category and degree. '
          'Your tracked applications stay on this phone either way.',
      action: FilledButton.icon(
        onPressed: () => _signIn(context, ref),
        icon: const Icon(Icons.login_rounded, size: 18),
        label: Text('Sign in with Google', style: text.labelLarge),
      ),
    );
  }
}

class _FinishProfileCard extends ConsumerWidget {
  const _FinishProfileCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _PromptCard(
        icon: Icons.badge_outlined,
        title: 'One minute to finish your profile',
        body: 'Date of birth, category and degree are all we need to filter jobs and count your seats.',
        action:
            FilledButton(onPressed: () => _openProfile(context, ref), child: const Text('Finish profile')),
      );
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.icon, required this.title, required this.body, required this.action});

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
