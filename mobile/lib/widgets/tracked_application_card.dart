import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/delivery_track.dart';
import '../domain/lifecycle.dart';
import '../domain/urgency.dart';
import '../models/tracked_application.dart';
import '../models/vault_entry.dart';
import '../providers/pin_providers.dart';
import '../providers/providers.dart';
import '../services/calendar_sync_service.dart';
import '../services/fx.dart';
import '../theme/app_theme.dart';
import '../utils/system_actions.dart';
import 'app_card.dart';
import 'app_icons.dart';
import 'common.dart';
import 'credential_drawer.dart';
import 'dashboard_check_sheet.dart';
import 'exam_delivery_tracker.dart';
import 'pills.dart';
import 'pin_dialog.dart';

enum _SyncState { idle, syncing, done }

enum _Panel { none, progress, credentials }

enum _MenuAction { admitCardLive, examScheduled, examDone, backToApplied, editLinks, delete }

/// A tracked exam: name, where it is now and the one next step, copyable
/// Reg/Roll numbers, Candidate login + Official site, and (tap the card) its
/// delivery-style progress track.
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
        Fx.done();
        if (!mounted) return;
        showCalmSnack(context,
            'Added $eventsWritten event${eventsWritten == 1 ? '' : 's'} with reminders at 7 days, 2 days and 3 hrs.');
      case final CalendarSyncFailure failure:
        setState(() => _sync = app.calendarSynced ? _SyncState.done : _SyncState.idle);
        showErrorSnack(context, failure.userMessage);
    }
  }

  Future<void> _onMenu(_MenuAction action) async {
    final notifier = ref.read(trackedAppsProvider.notifier);
    if (action != _MenuAction.delete) Fx.tap();
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
      case _MenuAction.examDone:
        // The exam's own first day if it has passed, else yesterday: either way the
        // track moves on to the answer key.
        final today = DateTime.now();
        final start = app.effectiveExamAt;
        final yesterday = DateTime(today.year, today.month, today.day - 1, 12);
        final when = start != null && start.isBefore(DateTime(today.year, today.month, today.day))
            ? start
            : yesterday;
        await notifier.setStatus(app.id, ApplicationStatus.examScheduled, examAt: when);
      case _MenuAction.backToApplied:
        await notifier.setStatus(app.id, ApplicationStatus.applied);
      case _MenuAction.editLinks:
        final links = await showDialog<(String, String)>(
          context: context,
          builder: (_) => _LinksDialog(login: app.applyUrl, official: app.portalUrl),
        );
        if (links == null) return;
        await notifier.setLinks(app.id, loginUrl: links.$1, officialUrl: links.$2);
      case _MenuAction.delete:
        if (!await _confirmDelete()) return;
        final name = app.postName;
        await notifier.untrack(app.id);
        if (mounted) showCalmSnack(context, 'Deleted $name');
    }
  }

  /// "Track Mains" / "Track Tier-2": the next stage becomes its own card.
  Future<void> _trackNextTier() async {
    final next = app.nextTierName;
    final current = app.tierName;
    await ref.read(trackedAppsProvider.notifier).trackNextTier(app);
    if (mounted) {
      showCalmSnack(context, 'Now tracking $next.${current == null ? '' : ' $current moved to the archive.'}');
    }
  }

  void _onTrackAction(StageAction action, {required bool nextTier}) {
    if (nextTier) {
      _trackNextTier();
    } else {
      openExternal(context, action.url);
    }
  }

  Future<bool> _confirmDelete() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppPalette.surface,
          title: const Text('Delete this exam?'),
          content: Text('${app.postName} goes from this phone and your backup, with its calendar '
              'reminders, saved IDs and password. Swipe left instead to just archive it.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;

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
    // Past dates too: an exam already written moves the track on to the answer key.
    final first = now.subtract(const Duration(days: 365));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first,
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
    final focus = app.focusDateAt(widget.now);
    final track = buildDeliveryTrack(app, widget.now);
    final vault = ref.watch(vaultEntryProvider(app.id)).dataOrNull;
    final hasPassword = ref.watch(hasPasswordProvider(app.id)).dataOrNull ?? false;
    final idsLocked = !(ref.watch(pinLockProvider).dataOrNull?.unlocked(DateTime.now()) ?? true);
    // With IDs saved, the login button becomes the quick "Check dashboard".
    final hasIds = hasPassword || !(vault?.isEmpty ?? true);

    return AppCard(
      // Tapping the card opens (or closes) its progress track.
      onTap: () => _toggle(_Panel.progress),
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
                child: _DatePill(app: app, now: widget.now),
              ),
              PopupMenuButton<_MenuAction>(
                tooltip: 'Update status, links or delete',
                onSelected: _onMenu,
                itemBuilder: (_) => [
                  if (app.status != ApplicationStatus.admitCardLive)
                    const PopupMenuItem(value: _MenuAction.admitCardLive, child: Text('Admit card is out')),
                  const PopupMenuItem(value: _MenuAction.examScheduled, child: Text('Set exam date')),
                  if (!app.examOver(widget.now))
                    const PopupMenuItem(value: _MenuAction.examDone, child: Text('Exam is done')),
                  if (app.status != ApplicationStatus.applied)
                    const PopupMenuItem(value: _MenuAction.backToApplied, child: Text('Back to “Applied”')),
                  const PopupMenuItem(value: _MenuAction.editLinks, child: Text('Edit links')),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: _MenuAction.delete,
                    child: Row(
                      children: [
                        DuoIcon(AppIcon.delete, size: 20, color: Theme.of(context).colorScheme.error),
                        const SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                    ),
                  ),
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusBadge(app: app, track: track),
                    if ((app.totalSeats ?? 0) > 0) // 0 = the notice didn't say
                      SeatPill(
                        total: app.totalSeats!,
                        ur: app.urSeats ?? 0,
                        quota: app.quotaSeats ?? 0,
                        category: app.category,
                      ),
                    ..._quickCopyChips(context, vault,
                        locked: idsLocked, onUnlock: () => ensureUnlocked(context, ref)),
                  ],
                ),
                // The one next step, without opening the track.
                if (_panel != _Panel.progress) ...[
                  const SizedBox(height: 10),
                  _NowLine(track: track, onAction: _onTrackAction),
                ],
                if (app.updates.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _LatestNotice(update: app.updates.first),
                ],
                const SizedBox(height: 12),
                // Side by side when they fit, else one under the other: labels never break.
                OverflowBar(
                  spacing: 8,
                  overflowSpacing: 6,
                  children: [
                    // With the track open, its card has the login (or a better step).
                    if (_panel != _Panel.progress)
                      _LinkButton(
                        icon: AppIcon.login,
                        label: hasIds ? 'Dashboard' : 'Login',
                        url: app.loginUrl,
                        onPressed: hasIds
                            ? () => showDashboardCheck(
                                  context,
                                  ref,
                                  app,
                                  onAdmitCardOut: () => _onMenu(_MenuAction.admitCardLive),
                                  onExamDone: () => _onMenu(_MenuAction.examDone),
                                )
                            : null,
                      ),
                    _LinkButton(icon: AppIcon.applyOnline, label: 'Official site', url: app.officialUrl),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _SyncButton(state: _sync, onPressed: _syncToCalendar),
                    _PanelToggle(
                      icon: AppIcon.timeline,
                      label: 'Progress',
                      open: _panel == _Panel.progress,
                      onPressed: () => _toggle(_Panel.progress),
                    ),
                    _PanelToggle(
                      icon: AppIcon.idVault,
                      label: 'IDs',
                      open: _panel == _Panel.credentials,
                      onPressed: () => _toggle(_Panel.credentials),
                    ),
                  ],
                ),
                Fold(
                  child: switch (_panel) {
                    _Panel.progress => Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: ExamDeliveryTracker(app: app, now: widget.now, onTrackNextTier: _trackNextTier),
                      ),
                    _Panel.credentials => Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: CredentialDrawer(app: app),
                      ),
                    _Panel.none => null,
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

/// Where the exam is now, as a small coloured badge in the header, read off the
/// progress track (so it moves on when the exam's dates pass, not only on notices).
/// 🟢 admit card · 🟡 exam · 🟣 answer key · 🔵 result.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.app, required this.track});

  final TrackedApplication app;
  final DeliveryTrack track;

  @override
  Widget build(BuildContext context) {
    final (Color color, AppIcon icon) = switch (track.finished || track.offersNextTier ? 4 : track.activeIndex) {
      1 => (AppPalette.sage, AppIcon.admitCard),
      2 => (AppPalette.honey, AppIcon.examDay),
      3 => (AppPalette.lavender, AppIcon.answerKey),
      4 || 5 => (AppPalette.periwinkle, AppIcon.result),
      _ => (AppPalette.textMuted, AppIcon.applied),
    };
    final label = track.statusLabel;
    final stage = app.tierName;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            glyph(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(stage == null ? label : '$stage · $label',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
            ),
            if (track.activeIndex == 2 && app.calendarSynced) ...[
              const SizedBox(width: 6),
              glyph(AppIcon.calendarDone, size: 14, color: AppPalette.sage),
            ],
          ],
        ),
      ),
    );
  }
}

/// The card's date: "Starts 12 Oct" / "Till 19 Oct" for an exam window, a
/// countdown for a single day, nothing once the exam is over (the badge then says
/// what comes next).
class _DatePill extends StatelessWidget {
  const _DatePill({required this.app, required this.now});

  final TrackedApplication app;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final start = app.effectiveExamAt;
    final end = app.examEnd;
    if (start != null && app.examOver(now)) return const SizedBox.shrink();
    final window = start != null &&
        end != null &&
        DateTime(end.year, end.month, end.day).isAfter(DateTime(start.year, start.month, start.day));
    if (!window) return CountdownPill(due: app.focusDateAt(now), now: now);
    final before = now.isBefore(start);
    return CountdownPill(
      due: before ? start : end,
      now: now,
      label: before ? 'Starts ${stageDateLabel(start)}' : 'Till ${stageDateLabel(end)}',
    );
  }
}

/// The track's one sentence, and its action when it is a real next step
/// (download, raise an objection, check the result, track the next stage).
class _NowLine extends StatelessWidget {
  const _NowLine({required this.track, required this.onAction});

  final DeliveryTrack track;
  final void Function(StageAction action, {required bool nextTier}) onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final action = track.action;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(track.headline, style: text.bodyMedium),
        if (action != null && action.primary) ...[
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => onAction(action, nextTier: track.offersNextTier),
            icon: DuoIcon(
                track.offersNextTier
                    ? AppIcon.addExam
                    : action.label.startsWith('Download')
                        ? AppIcon.download
                        : AppIcon.applyOnline,
                size: 18),
            label: Text(action.label),
          ),
        ],
      ],
    );
  }
}

/// Candidate login / Official site. Greyed out without a link (⋮ → Edit links).
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.icon, required this.label, required this.url, this.onPressed});

  final AppIcon icon;
  final String label;
  final String? url;

  /// Instead of just opening [url] (the "Check dashboard" sheet).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final link = url;
    return Tooltip(
      message: link ?? 'No link saved. Add one from ⋮ → Edit links.',
      child: OutlinedButton.icon(
        onPressed: link == null ? null : (onPressed ?? () => openExternal(context, link)),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
        icon: DuoIcon(icon, size: 18),
        label: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// One tap copies the Registration / Roll number, right on the card. With the PIN
/// lock on, one "Show IDs" chip until the PIN is entered.
List<Widget> _quickCopyChips(BuildContext context, VaultEntry? vault,
    {required bool locked, required VoidCallback onUnlock}) {
  final reg = vault?.registrationId;
  final roll = vault?.rollNumber;
  if (locked && ((reg ?? '').isNotEmpty || (roll ?? '').isNotEmpty)) {
    return [
      ActionChip(
        avatar: const Icon(Icons.lock_outline_rounded, size: 16),
        label: const Text('Show IDs'),
        tooltip: 'Enter your PIN to show Reg and Roll numbers',
        onPressed: onUnlock,
      ),
    ];
  }
  return [
    if (reg != null && reg.isNotEmpty)
      ActionChip(
        avatar: const DuoIcon(AppIcon.copy, size: 16),
        label: Text('Reg $reg'),
        tooltip: 'Copy registration number',
        onPressed: () => copyToClipboard(context, 'Registration number', reg),
      ),
    if (roll != null && roll.isNotEmpty)
      ActionChip(
        avatar: const DuoIcon(AppIcon.copy, size: 16),
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
      onTap: () => openExternal(context, update.open),
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            DuoIcon(AppIcon.newNotice, size: 16, color: AppPalette.periwinkle),
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

  final Object icon;
  final String label;
  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onPressed,
        icon: glyph(open ? Icons.expand_less_rounded : icon, size: 18),
        label: Text(open ? 'Hide' : label, maxLines: 1, softWrap: false),
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
          style: OutlinedButton.styleFrom(foregroundColor: sage, side: BorderSide(color: sage.withValues(alpha: 0.5))),
          icon: const DuoIcon(AppIcon.calendarDone, size: 18),
          label: const Text('In calendar', maxLines: 1, softWrap: false),
        ),
      _SyncState.idle => FilledButton.tonalIcon(
          onPressed: onPressed,
          icon: const DuoIcon(AppIcon.calendarAdd, size: 18),
          label: const Text('Calendar', maxLines: 1, softWrap: false),
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

/// ⋮ → Edit links: candidate login and official website. Returns (login, official).
class _LinksDialog extends StatefulWidget {
  const _LinksDialog({this.login, this.official});

  final String? login;
  final String? official;

  @override
  State<_LinksDialog> createState() => _LinksDialogState();
}

class _LinksDialogState extends State<_LinksDialog> {
  late final _login = TextEditingController(text: widget.login);
  late final _official = TextEditingController(text: widget.official);

  @override
  void dispose() {
    _login.dispose();
    _official.dispose();
    super.dispose();
  }

  static String _url(TextEditingController c) {
    final raw = c.text.trim();
    return raw.isEmpty || raw.startsWith(RegExp('https?://', caseSensitive: false)) ? raw : 'https://$raw';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: AppPalette.surface,
        title: const Text('Links'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _login,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Candidate login'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _official,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Official website'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, (_url(_login), _url(_official))),
            child: const Text('Save'),
          ),
        ],
      );
}
