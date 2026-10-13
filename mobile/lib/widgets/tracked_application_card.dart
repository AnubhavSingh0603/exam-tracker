import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/lifecycle.dart';
import '../domain/urgency.dart';
import '../models/tracked_application.dart';
import '../models/vault_entry.dart';
import '../providers/providers.dart';
import '../services/calendar_sync_service.dart';
import '../theme/app_theme.dart';
import '../utils/system_actions.dart';
import 'app_card.dart';
import 'credential_drawer.dart';
import 'exam_lifecycle_stepper.dart';
import 'pills.dart';

enum _SyncState { idle, syncing, done }

enum _Panel { none, timeline, credentials }

enum _MenuAction { admitCardLive, examScheduled, backToApplied }

class TrackedApplicationCard extends ConsumerStatefulWidget {
  const TrackedApplicationCard({super.key, required this.app, required this.now});

  final TrackedApplication app;
  final DateTime now;

  @override
  ConsumerState<TrackedApplicationCard> createState() => _TrackedApplicationCardState();
}

class _TrackedApplicationCardState extends ConsumerState<TrackedApplicationCard> {
  _Panel _panel = _Panel.none;
  _SyncState _sync = _SyncState.idle;

  TrackedApplication get app => widget.app;

  @override
  void initState() {
    super.initState();
    if (app.calendarSynced) _sync = _SyncState.done;
  }

  @override
  void didUpdateWidget(TrackedApplicationCard old) {
    super.didUpdateWidget(old);
    if (_sync != _SyncState.syncing) {
      _sync = app.calendarSynced ? _SyncState.done : _SyncState.idle;
    }
  }

  void _toggle(_Panel panel) => setState(() => _panel = _panel == panel ? _Panel.none : panel);

  Future<void> _syncToCalendar() async {
    setState(() => _sync = _SyncState.syncing);
    final result = await ref.read(calendarSyncProvider).syncExamToCalendar(app);
    await ref.read(trackedAppsProvider.notifier).reload();
    if (!mounted) return;
    switch (result) {
      case CalendarSyncSuccess(:final eventsWritten):
        setState(() => _sync = _SyncState.done);
        await HapticFeedback.mediumImpact();
        if (!mounted) return;
        showCalmSnack(context,
            'Added $eventsWritten event${eventsWritten == 1 ? '' : 's'} with reminders at 7 days, 2 days and 3 hrs.');
      case final CalendarSyncFailure failure:
        setState(() => _sync = app.calendarSynced ? _SyncState.done : _SyncState.idle);
        showCalmSnack(context, failure.userMessage);
    }
  }

  Future<void> _onMenu(_MenuAction action) async {
    final notifier = ref.read(trackedAppsProvider.notifier);
    switch (action) {
      case _MenuAction.admitCardLive:
        final url = await _askAdmitCardUrl();
        if (url == null) return; // dialog cancelled
        await notifier.setStatus(app.id, ApplicationStatus.admitCardLive,
            admitCardUrl: url.isEmpty ? null : url);
      case _MenuAction.examScheduled:
        final when = await _pickExamDateTime();
        if (when == null) return;
        await notifier.setStatus(app.id, ApplicationStatus.examScheduled, examAt: when);
        // Keep the phone calendar honest if it was already synced.
        if (app.calendarSynced && mounted) await _syncAfterReload();
      case _MenuAction.backToApplied:
        await notifier.setStatus(app.id, ApplicationStatus.applied);
    }
  }

  Future<void> _syncAfterReload() async {
    final fresh = await ref.read(databaseProvider).getApplication(app.id);
    if (fresh == null || !mounted) return;
    await ref.read(calendarSyncProvider).syncExamToCalendar(fresh);
    await ref.read(trackedAppsProvider.notifier).reload();
  }

  /// null = cancelled, '' = saved without a link.
  Future<String?> _askAdmitCardUrl() => showDialog<String>(
        context: context,
        builder: (_) => _AdmitCardDialog(initial: app.admitCardUrl),
      );

  Future<DateTime?> _pickExamDateTime() async {
    final now = DateTime.now();
    final initial = app.examAt?.toLocal() ?? now.add(const Duration(days: 30));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 730)),
      helpText: 'Exam date',
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(app.examAt?.toLocal() ?? DateTime(0, 1, 1, 9)),
      helpText: 'Reporting time',
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.urgencyColors;
    final focus = app.focusDate;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return AppCard(
      accent: colors.of(urgencyFor(focus, widget.now)),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(app.postName, style: text.titleMedium),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: CountdownPill(due: focus, now: widget.now),
              ),
              PopupMenuButton<_MenuAction>(
                tooltip: 'Update status',
                onSelected: _onMenu,
                itemBuilder: (_) => [
                  if (app.status != ApplicationStatus.admitCardLive)
                    const PopupMenuItem(value: _MenuAction.admitCardLive, child: Text('Admit card is out')),
                  const PopupMenuItem(value: _MenuAction.examScheduled, child: Text('Set exam date')),
                  if (app.status != ApplicationStatus.applied)
                    const PopupMenuItem(value: _MenuAction.backToApplied, child: Text('Back to “Applied”')),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (app.examName != app.postName) Text(app.examName, style: text.bodySmall),
                const SizedBox(height: 10),
                _MilestoneBadge(app: app, now: widget.now),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (app.totalSeats != null)
                      SeatPill(
                        total: app.totalSeats!,
                        ur: app.urSeats ?? 0,
                        quota: app.quotaSeats ?? 0,
                        category: app.category,
                      ),
                    ..._quickCopyChips(context, ref.watch(vaultEntryProvider(app.id)).dataOrNull),
                  ],
                ),
                if (app.updates.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _LatestNotice(update: app.updates.first),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _SyncButton(state: _sync, onPressed: _syncToCalendar)),
                    const SizedBox(width: 4),
                    _PanelToggle(
                      icon: Icons.timeline_rounded,
                      label: 'Timeline',
                      open: _panel == _Panel.timeline,
                      onPressed: () => _toggle(_Panel.timeline),
                    ),
                    _PanelToggle(
                      icon: Icons.key_rounded,
                      label: 'IDs',
                      open: _panel == _Panel.credentials,
                      onPressed: () => _toggle(_Panel.credentials),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: switch (_panel) {
                    _Panel.timeline => Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: ExamLifecycleStepper(app: app, now: widget.now),
                      ),
                    _Panel.credentials => Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: CredentialDrawer(app: app),
                      ),
                    _Panel.none => const SizedBox(width: double.infinity),
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Live status from the exam watcher (or the user), with the one action that
/// matters at that stage. 🟢 admit card · 🟡 exam · 🟣 answer key · 🔵 result.
class _MilestoneBadge extends StatelessWidget {
  const _MilestoneBadge({required this.app, required this.now});

  final TrackedApplication app;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final t = app.timeline;
    final status = app.displayStatus;
    final (Color color, IconData icon) = switch (status) {
      TrackerStatus.applied => (AppPalette.textMuted, Icons.hourglass_top_rounded),
      TrackerStatus.admitCardLive => (AppPalette.sage, Icons.badge_rounded),
      TrackerStatus.examScheduled => (AppPalette.honey, Icons.event_rounded),
      TrackerStatus.answerKeyLive => (AppPalette.lavender, Icons.fact_check_rounded),
      TrackerStatus.resultDeclared => (AppPalette.periwinkle, Icons.emoji_events_rounded),
    };
    final exam = app.effectiveExamAt;
    final objection = t?.objectionDeadline;
    final objectionOpen =
        status == TrackerStatus.answerKeyLive && objection != null && !objection.isBefore(now);

    final (String? actionLabel, String? actionUrl) = switch (status) {
      TrackerStatus.admitCardLive => (
          'Download admit card',
          app.latestUpdate('admit_card')?.url ?? t?.admitCardUrl ?? app.admitCardUrl ?? app.portalUrl,
        ),
      TrackerStatus.answerKeyLive => (
          'View answer key',
          app.latestUpdate('answer_key')?.url ?? t?.answerKeyUrl
        ),
      TrackerStatus.resultDeclared => (
          'Merit list',
          app.latestUpdate('result')?.url ?? t?.meritListUrl ?? t?.scorecardUrl,
        ),
      _ => (null, null),
    };

    final subtitle = switch (status) {
      TrackerStatus.applied => (app.portalUrl ?? '').isNotEmpty
          ? 'Watching its portal and job sites for admit card, dates and results'
          : 'Watching job sites for admit card, dates and results',
      TrackerStatus.examScheduled when exam != null => stageDateLabel(exam, t?.examEnd),
      _ => null,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(status.label, style: text.titleSmall?.copyWith(color: color)),
                ),
              ),
              if (status == TrackerStatus.examScheduled && app.calendarSynced)
                const _MiniChip(label: 'Calendar Synced', icon: Icons.event_available_rounded),
              if (objectionOpen)
                CountdownPill(
                    due: DateTime(objection.year, objection.month, objection.day, 23, 59), now: now),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: text.bodySmall),
          ],
          if (objectionOpen) ...[
            const SizedBox(height: 4),
            Text('Objection window closes ${stageDateLabel(objection)}', style: text.bodySmall),
          ],
          if (actionLabel != null && actionUrl != null) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => openExternal(context, actionUrl),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(actionLabel),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final sage = context.urgencyColors.safe;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: sage.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: sage),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: sage)),
        ],
      ),
    );
  }
}

/// One tap copies the Registration / Roll number, right on the card.
List<Widget> _quickCopyChips(BuildContext context, VaultEntry? vault) {
  final reg = vault?.registrationId;
  final roll = vault?.rollNumber;
  return [
    if (reg != null && reg.isNotEmpty)
      ActionChip(
        avatar: const Icon(Icons.copy_rounded, size: 16),
        label: Text('Reg $reg'),
        tooltip: 'Copy registration number',
        onPressed: () => copyToClipboard(context, 'Registration number', reg),
      ),
    if (roll != null && roll.isNotEmpty)
      ActionChip(
        avatar: const Icon(Icons.copy_rounded, size: 16),
        label: Text('Roll $roll'),
        tooltip: 'Copy roll number',
        onPressed: () => copyToClipboard(context, 'Roll number', roll),
      ),
  ];
}

/// The exam watcher's newest notice, tappable.
class _LatestNotice extends StatelessWidget {
  const _LatestNotice({required this.update});

  final ExamUpdate update;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => openExternal(context, update.url),
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.notifications_active_outlined, size: 16, color: AppPalette.periwinkle),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                update.title,
                style: text.bodySmall?.copyWith(color: AppPalette.textPrimary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelToggle extends StatelessWidget {
  const _PanelToggle({required this.icon, required this.label, required this.open, required this.onPressed});

  final IconData icon;
  final String label;
  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onPressed,
        icon: Icon(open ? Icons.expand_less_rounded : icon, size: 18),
        label: Text(open ? 'Hide' : label),
      );
}

class _SyncButton extends StatelessWidget {
  const _SyncButton({required this.state, required this.onPressed});

  final _SyncState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final sage = context.urgencyColors.safe;
    return switch (state) {
      _SyncState.syncing => const OutlinedButton(
          onPressed: null,
          child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      _SyncState.done => OutlinedButton.icon(
          // Tapping again re-syncs (e.g. after editing dates) — it updates, never duplicates.
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
              foregroundColor: sage, side: BorderSide(color: sage.withValues(alpha: 0.5))),
          icon: const Icon(Icons.event_available_rounded, size: 18),
          label: const Text('In calendar'),
        ),
      _SyncState.idle => FilledButton.tonalIcon(
          onPressed: onPressed,
          icon: const Icon(Icons.edit_calendar_rounded, size: 18),
          label: const Text('Sync to Calendar'),
        ),
    };
  }
}

/// Owns its controller so it is disposed only after the route has fully closed.
class _AdmitCardDialog extends StatefulWidget {
  const _AdmitCardDialog({this.initial});

  final String? initial;

  @override
  State<_AdmitCardDialog> createState() => _AdmitCardDialogState();
}

class _AdmitCardDialogState extends State<_AdmitCardDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: AppPalette.surface,
        title: const Text('Admit card is out'),
        content: TextField(
          controller: _controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Download link (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      );
}
