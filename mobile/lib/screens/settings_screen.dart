import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/env.dart';
import '../models/job_preferences.dart';
import '../models/user_profile.dart';
import '../providers/account_providers.dart';
import '../providers/backup_providers.dart';
import '../providers/jobs_providers.dart';
import '../providers/providers.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/system_actions.dart';
import '../widgets/common.dart';
import '../widgets/samsung_sleep_tip.dart';
import '../widgets/update_dialog.dart';
import 'home_shell.dart';

enum SettingsTab {
  account('Account'),
  profile('Profile'),
  jobs('Jobs'),
  alerts('Alerts'),
  about('About');

  const SettingsTab(this.label);
  final String label;
}

const kHomePage = 'https://anubhavsingh0603.github.io/exam-tracker/';
const kPrivacyPolicy = 'https://anubhavsingh0603.github.io/exam-tracker/privacy.html';
const kIssues = 'https://github.com/AnubhavSingh0603/exam-tracker/issues';

/// Account & settings, one page per topic.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.initialTab = SettingsTab.account});

  final SettingsTab initialTab;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: SettingsTab.values.length,
        initialIndex: initialTab.index,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Account & settings'),
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppPalette.periwinkle,
              labelColor: AppPalette.textPrimary,
              unselectedLabelColor: AppPalette.textMuted,
              dividerColor: AppPalette.outline,
              tabs: [for (final t in SettingsTab.values) Tab(text: t.label)],
            ),
          ),
          body: const TabBarView(
            children: [_AccountTab(), _ProfileTab(), _JobsTab(), _AlertsTab(), _AboutTab()],
          ),
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.note});

  final String title;
  final String? note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppPalette.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleMedium),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(note!, style: text.bodySmall),
          ],
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Account
// -----------------------------------------------------------------------------

class _AccountTab extends ConsumerWidget {
  const _AccountTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(googleAccountProvider).dataOrNull;
    final backup = ref.watch(backupControllerProvider);
    final now = ref.watch(nowProvider);
    final text = Theme.of(context).textTheme;
    final backups = ref.read(backupControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: 'Google account',
          note: 'Used only to back up your data to your own Google Drive, so a new phone gets it all back.',
          children: [
            if (!Env.canSignIn)
              const MutedNote('Backup isn’t set up in this build.')
            else if (user == null) ...[
              const MutedNote('Not signed in. Everything stays on this phone only.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => signInWithGoogle(context, ref),
                icon: const Icon(Icons.login_rounded),
                label: const Text('Sign in with Google'),
              ),
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppPalette.surfaceVariant,
                  child: Text(user.initial, style: text.titleMedium?.copyWith(color: AppPalette.periwinkle)),
                ),
                title: Text(user.name ?? user.email),
                subtitle: Text(user.email),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    backup.phase == BackupPhase.idle ? Icons.cloud_done_rounded : Icons.cloud_sync_rounded,
                    size: 18,
                    color: AppPalette.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(backupStatusLabel(backup, now), style: text.bodySmall)),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (backup.phase == BackupPhase.needsPermission)
                    FilledButton(
                      onPressed: () async {
                        try {
                          await backups.allowDrive();
                        } on AuthException catch (e) {
                          if (!e.cancelled && context.mounted) showCalmSnack(context, e.message);
                        }
                      },
                      child: const Text('Allow Drive backup'),
                    )
                  else
                    FilledButton.tonal(
                      onPressed: () async {
                        final outcome = await backups.sync();
                        if (!context.mounted) return;
                        showCalmSnack(
                          context,
                          outcome != null
                              ? 'Backed up to your Google Drive.'
                              : backupStatusLabel(ref.read(backupControllerProvider), DateTime.now()),
                        );
                      },
                      child: const Text('Back up now'),
                    ),
                  OutlinedButton(
                    onPressed: () async {
                      await ref.read(googleAccountProvider.notifier).signOut();
                      if (context.mounted) {
                        showCalmSnack(context, 'Signed out. Your data stays on this phone.');
                      }
                    },
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Profile
// -----------------------------------------------------------------------------

class _ProfileTab extends ConsumerWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).dataOrNull;
    final now = ref.watch(nowProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: 'Your profile',
          note:
              'Used on this phone to decide which jobs you qualify for and how many seats you can compete for.',
          children: [
            if (profile == null)
              const MutedNote('No profile yet.')
            else ...[
              _Fact('Name', profile.displayName),
              _Fact('Age', '${ageOn(profile.dateOfBirth, now)} years'),
              _Fact('Category', profile.category.label),
              _Fact('Qualification', profile.qualificationLabel),
              _Fact('Experience', experienceLabel(profile.experienceYears)),
              if (profile.isPwbd) const _Fact('PwBD', 'Yes'),
              if (profile.isExServiceman)
                _Fact('Ex-serviceman', '${profile.exServicemanServiceYears} years of service'),
            ],
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => openProfileSheet(context, ref),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: Text(profile == null ? 'Set up profile' : 'Edit profile'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 120, child: Text(label, style: text.bodyMedium?.copyWith(color: AppPalette.textMuted))),
          Expanded(child: Text(value, style: text.bodyMedium)),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Jobs: what to show and in which order
// -----------------------------------------------------------------------------

const _typeLabels = {
  'permanent': 'Permanent',
  'contract': 'Contract',
  'apprenticeship': 'Apprenticeship',
  'fellowship': 'Fellowship',
  'internship': 'Internship',
};

class _JobsTab extends ConsumerWidget {
  const _JobsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(jobPreferencesProvider).dataOrNull ?? JobPreferences.defaults;
    final decisions = ref.watch(decisionsProvider).dataOrNull ?? const <JobDecision>[];
    final applied = decisions.where((d) => d.applied).length;
    void save(JobPreferences p) => ref.read(jobPreferencesProvider.notifier).save(p);
    Set<T> toggle<T>(Set<T> set, T value) =>
        set.contains(value) ? ({...set}..remove(value)) : {...set, value};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: 'Show these first',
          note: 'Picked groups rank above the rest. None picked: railways, banks, SSC, UPSC and PSUs lead.',
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in JobCategory.values)
                  FilterChip(
                    label: Text(c.label),
                    selected: prefs.preferred.contains(c),
                    onSelected: (_) => save(prefs.copyWith(
                      preferred: toggle(prefs.preferred, c),
                      hidden: {...prefs.hidden}..remove(c),
                    )),
                  ),
              ],
            ),
          ],
        ),
        _Section(
          title: 'Never show',
          note: 'Hidden groups disappear from Jobs and Today.',
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in JobCategory.values)
                  FilterChip(
                    label: Text(c.label),
                    selected: prefs.hidden.contains(c),
                    selectedColor: AppPalette.terracotta.withValues(alpha: 0.2),
                    onSelected: (_) => save(prefs.copyWith(
                      hidden: toggle(prefs.hidden, c),
                      preferred: {...prefs.preferred}..remove(c),
                    )),
                  ),
              ],
            ),
          ],
        ),
        _Section(
          title: 'Filters',
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: prefs.hideBelowMyLevel,
              onChanged: (v) => save(prefs.copyWith(hideBelowMyLevel: v)),
              title: const Text('Hide jobs that only need 10th pass'),
              subtitle: const Text('For graduates: peon, chowkidar, gardener, MTS and similar posts.'),
            ),
            const SizedBox(height: 8),
            Text(
              prefs.minMonthlyPay == 0 ? 'Any pay' : 'At least ₹${prefs.minMonthlyPay ~/ 1000}k a month',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Slider(
              value: prefs.minMonthlyPay.toDouble(),
              max: 100000,
              divisions: 20,
              label: prefs.minMonthlyPay == 0 ? 'Any' : '₹${prefs.minMonthlyPay ~/ 1000}k',
              onChanged: (v) => save(prefs.copyWith(minMonthlyPay: v.round())),
            ),
            const MutedNote('Jobs that don’t state their pay are always kept.'),
            const SizedBox(height: 12),
            Text('Hide these job types', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final MapEntry(key: type, value: label) in _typeLabels.entries)
                  FilterChip(
                    label: Text(label),
                    selected: prefs.hiddenTypes.contains(type),
                    onSelected: (_) => save(prefs.copyWith(hiddenTypes: toggle(prefs.hiddenTypes, type))),
                  ),
              ],
            ),
          ],
        ),
        _Section(
          title: 'Languages you can work in',
          note: 'Posts about another language (a Marathi teacher, a Tamil translator) are hidden.',
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final lang in kIndianLanguages)
                  FilterChip(
                    label: Text(lang),
                    selected: prefs.languages.contains(lang),
                    onSelected: (_) => save(prefs.copyWith(languages: toggle(prefs.languages, lang))),
                  ),
              ],
            ),
          ],
        ),
        _Section(
          title: 'Learning from your choices',
          note: 'Jobs like the ones you apply to move up; jobs like the ones you swipe away move down. '
              'This stays on your phone and in your backup.',
          children: [
            Text('Learned from $applied applied and ${decisions.length - applied} not-for-me.',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: decisions.isEmpty
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          backgroundColor: AppPalette.surface,
                          title: const Text('Start learning again?'),
                          content: const Text('Jobs you hid come back, and ranking forgets your history. '
                              'Your tracked exams are not touched.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reset')),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      for (final d in decisions) {
                        await ref.read(decisionsProvider.notifier).undo(d.jobPostId);
                      }
                    },
              child: const Text('Reset'),
            ),
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Alerts
// -----------------------------------------------------------------------------

class _AlertsTab extends ConsumerWidget {
  const _AlertsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Exam updates',
            note: 'Every few hours the app checks job sites and exam websites for admit cards, exam dates, '
                'answer keys and results for the exams you applied to.',
            children: [
              FilledButton.tonal(
                onPressed: () => allowBackgroundChecks(context),
                child: const Text('Allow background checks'),
              ),
              const SizedBox(height: 8),
              FutureBuilder<bool>(
                future: isSamsungPhone(),
                builder: (context, snap) => snap.data == true
                    ? TextButton(
                        onPressed: () => showSamsungSleepTip(context),
                        child: const Text('Samsung: keep the app awake'),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          const _Section(
            title: 'Notifications',
            note: 'Turn them on in Android settings if you said no earlier.',
            children: [
              OutlinedButton(onPressed: openAppSettings, child: Text('Open app settings')),
            ],
          ),
          const _Section(
            title: 'Calendar reminders',
            note: 'Use “Sync to Calendar” on an exam in My exams. Reminders come 7 days, 2 days and '
                '3 hours before, from your phone’s Calendar app, so they arrive even if this app is asleep.',
            children: [],
          ),
        ],
      );
}

// -----------------------------------------------------------------------------
// About
// -----------------------------------------------------------------------------

class _AboutTab extends ConsumerWidget {
  const _AboutTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: 'ApplyTrack',
          note: 'One clear next step. Less to keep in mind.',
          children: [
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snap) => Text(
                snap.hasData ? 'Version ${snap.data!.version}' : 'Version …',
                style: text.bodyMedium,
              ),
            ),
            const SizedBox(height: 12),
            if (Env.updatesEnabled)
              FilledButton.tonal(
                onPressed: () async {
                  final service = ref.read(updateServiceProvider);
                  final check = await service.check(force: true);
                  if (!context.mounted) return;
                  if (check == null) {
                    showCalmSnack(context, 'You have the latest version.');
                  } else {
                    await showUpdateDialog(context, service, check);
                  }
                },
                child: const Text('Check for updates'),
              ),
          ],
        ),
        _Section(
          title: 'Links',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.home_outlined),
              title: const Text('Home page'),
              onTap: () => openExternal(context, kHomePage),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy policy'),
              onTap: () => openExternal(context, kPrivacyPolicy),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('Report a problem'),
              onTap: () => openExternal(context, kIssues),
            ),
          ],
        ),
      ],
    );
  }
}
