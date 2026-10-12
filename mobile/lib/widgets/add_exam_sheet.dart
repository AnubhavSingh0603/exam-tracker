import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';

/// Track an exam applied to outside the feed. The server's exam watcher then
/// follows its portal for admit card, dates, answer key and result.
Future<void> showAddExamSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _AddExamSheet(),
    );

class _AddExamSheet extends ConsumerStatefulWidget {
  const _AddExamSheet();

  @override
  ConsumerState<_AddExamSheet> createState() => _AddExamSheetState();
}

class _AddExamSheetState extends ConsumerState<_AddExamSheet> {
  final _name = TextEditingController();
  final _link = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _link.dispose();
    super.dispose();
  }

  String? _normalisedLink() {
    final raw = _link.text.trim();
    if (raw.isEmpty) return null;
    return raw.startsWith(RegExp('https?://', caseSensitive: false)) ? raw : 'https://$raw';
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 3) {
      setState(() => _error = 'Type the exam name, e.g. SSC CGL 2026.');
      return;
    }
    final link = _normalisedLink();
    if (link != null && Uri.tryParse(link)?.host.contains('.') != true) {
      setState(() => _error = 'That link doesn’t look right. Leave it empty if unsure.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final app = await ref.read(trackedAppsProvider.notifier).addManual(examName: name, portalUrl: link);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text(app.id.startsWith('local-')
            ? 'Added on this phone. Automatic updates need you signed in and online.'
            : 'Added. We’ll watch for its admit card, dates and results.'),
      ));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not add it right now. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add an exam you applied to', style: text.titleLarge),
          const SizedBox(height: 4),
          Text(
            'For exams that weren’t in your feed. We’ll watch its notice board for you.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.next,
            maxLength: 300,
            decoration:
                const InputDecoration(labelText: 'Exam name', hintText: 'e.g. SSC CGL 2026', counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _link,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(
              labelText: 'Official portal link (optional)',
              hintText: 'e.g. ssc.gov.in or the recruitment page',
            ),
          ),
          const SizedBox(height: 6),
          Text('The recruitment’s own page works best. Without a link we rely on trusted job sites.',
              style: text.bodySmall),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: text.bodyMedium?.copyWith(color: AppPalette.terracotta)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Start tracking'),
          ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

/// Quiet "+ Add exam" link for the Tracking header.
class AddExamButton extends StatelessWidget {
  const AddExamButton({super.key});

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: () => showAddExamSheet(context),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Add exam'),
      );
}
