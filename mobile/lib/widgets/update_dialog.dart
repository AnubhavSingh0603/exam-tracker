import 'dart:async';

import 'package:flutter/material.dart';

import '../config/env.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../utils/system_actions.dart';

/// Calm update prompt: one decision, plain notes, a visible progress bar.
/// Non-blocking unless the installed version is below `min_supported`.
Future<void> showUpdateDialog(BuildContext context, UpdateService service, UpdateCheck check) =>
    showDialog<void>(
      context: context,
      barrierDismissible: !check.mandatory,
      builder: (_) => _UpdateDialog(service: service, check: check),
    );

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.service, required this.check});

  final UpdateService service;
  final UpdateCheck check;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  UpdateProgress? _progress;
  StreamSubscription<UpdateProgress>? _sub;

  UpdateInfo get info => widget.check.info;
  bool get _busy => _progress is UpdateDownloading || _progress is UpdateInstalling;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() => _progress = const UpdateDownloading(0));
    _sub?.cancel();
    _sub = widget.service.download(info).listen((p) {
      if (mounted) setState(() => _progress = p);
    });
  }

  Future<void> _later() async {
    await widget.service.skip(info.versionCode);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.urgencyColors;
    final size = info.sizeLabel;

    return PopScope(
      canPop: !widget.check.mandatory && !_busy,
      child: Dialog(
        backgroundColor: AppPalette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppPalette.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.system_update_rounded, color: colors.info),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Update available', style: text.titleLarge)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'v${widget.check.installedVersionName} → v${info.versionName}${size == null ? '' : ' · $size'}',
                style: text.bodySmall,
              ),
              if (widget.check.mandatory) ...[
                const SizedBox(height: 10),
                Text('This version is needed to keep syncing with the server.',
                    style: text.bodyMedium?.copyWith(color: colors.warning)),
              ],
              if (info.releaseNotes.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppPalette.surfaceVariant,
                      borderRadius: BorderRadius.circular(AppRadii.control),
                    ),
                    child: SingleChildScrollView(child: Text(info.releaseNotes.trim(), style: text.bodyMedium)),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              ..._body(context),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.urgencyColors;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    switch (_progress) {
      case null:
        return [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!widget.check.mandatory) TextButton(onPressed: _later, child: const Text('Later')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _start, child: const Text('Update now')),
            ],
          ),
        ];
      case UpdateDownloading(:final fraction):
        return [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: reduceMotion ? (fraction ?? 0) : fraction,
              minHeight: 8,
              color: colors.info,
              backgroundColor: AppPalette.surfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(fraction == null ? 'Downloading…' : 'Downloading… ${(fraction * 100).round()}%', style: text.bodySmall),
          const SizedBox(height: 8),
        ];
      case UpdateInstalling():
        return [
          Text('Opening the Android installer. Tap “Update” there to finish.', style: text.bodyMedium),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _start, child: const Text('Installer didn’t open? Retry')),
          ),
        ];
      case UpdateFailed(:final message, :final suggestSettings):
        return [
          Text(message, style: text.bodyMedium?.copyWith(color: colors.urgent)),
          if (suggestSettings) ...[
            const SizedBox(height: 8),
            Text(
              'Settings → Apps → Exam Tracker → Install unknown apps → Allow.\n'
              'On Samsung phones also check Settings → Security and privacy → Auto Blocker.',
              style: text.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              if (Env.releasesPageUrl.isNotEmpty)
                TextButton(
                  onPressed: () => openExternal(context, Env.releasesPageUrl),
                  child: const Text('Open download page'),
                ),
              FilledButton(onPressed: _start, child: const Text('Try again')),
            ],
          ),
        ];
    }
  }
}
