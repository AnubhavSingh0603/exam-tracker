import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/backup_providers.dart';
import '../providers/pin_providers.dart';
import '../theme/app_theme.dart';
import '../utils/system_actions.dart';

/// What the PIN dialog returns: the digits, or "Forgot PIN".
sealed class PinEntry {
  const PinEntry();
}

final class PinTyped extends PinEntry {
  const PinTyped(this.pin);
  final String pin;
}

final class PinForgot extends PinEntry {
  const PinForgot();
}

/// Four digits, hidden. Closes by itself on the fourth digit.
Future<PinEntry?> askForPin(BuildContext context,
        {required String title, String? message, String? error, bool offerForgot = true}) =>
    showDialog<PinEntry>(
      context: context,
      builder: (_) => _PinDialog(title: title, message: message, error: error, offerForgot: offerForgot),
    );

/// True when saved IDs may be shown: no PIN set, unlocked recently, or the right
/// PIN entered now. False when cancelled.
Future<bool> ensureUnlocked(BuildContext context, WidgetRef ref) async {
  final lock = ref.read(pinLockProvider.notifier);
  if ((await ref.read(pinLockProvider.future)).unlocked(DateTime.now())) return true;
  if (!context.mounted) return false;
  String? error;
  while (true) {
    if (!context.mounted) return false;
    final entry = await askForPin(context, title: 'Enter your PIN', message: 'To show your saved IDs.', error: error);
    if (entry == null || !context.mounted) return false;
    if (entry is PinForgot) {
      await confirmForgotPin(context, ref);
      return false;
    }
    switch (await lock.unlock((entry as PinTyped).pin)) {
      case PinOk():
        return true;
      case PinWrong(:final triesLeft):
        error = 'Wrong PIN. $triesLeft ${triesLeft == 1 ? 'try' : 'tries'} left.';
      case PinWait(:final until):
        error = 'Too many tries. Wait ${until.difference(DateTime.now()).inSeconds + 1} seconds.';
    }
  }
}

/// "Forgot PIN?": explain, then remove the PIN with the IDs saved on this phone.
Future<void> confirmForgotPin(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppPalette.surface,
          title: const Text('Forgot your PIN?'),
          content: const Text('This removes the PIN and the Reg/Roll numbers and passwords saved on this '
              'phone, so nobody can skip the PIN to read them. If Google backup is on, they come back '
              'from your Drive at the next backup.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove PIN and IDs')),
          ],
        ),
      ) ??
      false;
  if (!ok) return;
  await ref.read(pinLockProvider.notifier).forget();
  ref.read(backupControllerProvider.notifier).markDirty();
  if (context.mounted) showCalmSnack(context, 'PIN removed, with the IDs saved on this phone.');
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title, this.message, this.error, required this.offerForgot});

  final String title;
  final String? message;
  final String? error;
  final bool offerForgot;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      backgroundColor: AppPalette.surface,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message != null) Text(widget.message!, style: text.bodyMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 4,
            style: text.headlineSmall?.copyWith(letterSpacing: 16),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(counterText: '', hintText: '••••'),
            onChanged: (v) {
              if (v.length == 4) Navigator.pop(context, PinTyped(v));
            },
          ),
          if (widget.error != null) ...[
            const SizedBox(height: 8),
            Text(widget.error!, style: text.bodyMedium?.copyWith(color: AppPalette.terracotta)),
          ],
        ],
      ),
      actions: [
        if (widget.offerForgot)
          TextButton(onPressed: () => Navigator.pop(context, const PinForgot()), child: const Text('Forgot PIN?')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}
