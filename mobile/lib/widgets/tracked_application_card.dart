import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/urgency.dart';
import '../models/tracked_application.dart';
import '../providers/providers.dart';
import '../services/calendar_sync_service.dart';
import '../theme/app_theme.dart';
import '../utils/system_actions.dart';
import 'app_card.dart';
import 'credential_drawer.dart';
import 'pills.dart';

enum _SyncState { idle, syncing, done }

enum _MenuAction { admitCardLive, examScheduled, backToApplied }

class TrackedApplicationCard extends ConsumerStatefulWidget {
  const TrackedApplicationCard({super.key, required this.app, required this.now});

  final TrackedApplication app;
  final DateTime now;

  @override
  ConsumerState<TrackedApplicationCard> createState() => _TrackedApplicationCardState();
}

class _TrackedApplicationCardState extends ConsumerState<TrackedApplicationCard> {
  bool _expanded = false;
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
        await notifier.setStatus(app.id, ApplicationStatus.admitCardLive, admitCardUrl: url.isEmpty ? null : url);
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
                Text(app.examName, style: text.bodySmall),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StatusPill(label: app.status.label),
                    if (app.totalSeats != null)
                      SeatPill(
                        total: app.totalSeats!,
                        ur: app.urSeats ?? 0,
                        quota: app.quotaSeats ?? 0,
                        category: app.category,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _SyncButton(state: _sync, onPressed: _syncToCalendar)),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      icon: Icon(_expanded ? Icons.expand_less_rounded : Icons.key_rounded, size: 18),
                      label: Text(_expanded ? 'Hide' : 'Credentials'),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _expanded
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: CredentialDrawer(app: app),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
          style: OutlinedButton.styleFrom(foregroundColor: sage, side: BorderSide(color: sage.withValues(alpha: 0.5))),
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
