import 'package:flutter/material.dart';

import '../services/fx.dart';
import '../services/review_service.dart';
import '../utils/system_actions.dart';

/// Settings › About › Send a review: stars, what to fix or add, and an email if
/// you'd like a reply. Goes to the team's Google Form.
Future<void> showReviewSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ReviewSheet(),
    );

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet();

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _stars = 0;
  final _text = TextEditingController();
  final _email = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await ReviewService().send(stars: _stars, text: _text.text, email: _email.text);
      Fx.done();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('Thank you! Your review was sent.')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      showErrorSnack(context, 'Couldn’t send it. Check your internet and try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Send a review', style: text.titleLarge),
            const SizedBox(height: 4),
            Text('How is JobSummit working for you?', style: text.bodyMedium),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    tooltip: '$i star${i == 1 ? '' : 's'}',
                    iconSize: 40,
                    onPressed: _sending ? null : () => setState(() => _stars = i),
                    icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: i <= _stars ? colors.primary : null),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              minLines: 3,
              maxLines: 8,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What should we add or fix?',
                hintText: 'Optional',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Your email',
                hintText: 'Optional, only if you’d like a reply',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text('Sent with the app version and phone model, to help fix problems.', style: text.bodySmall),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _stars == 0 || _sending ? null : _send,
              child: Text(_sending
                  ? 'Sending…'
                  : _stars == 0
                      ? 'Pick a rating to send'
                      : 'Send'),
            ),
          ],
        ),
      ),
    );
  }
}
