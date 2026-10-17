import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';
import '../models/jobs_data.dart';
import '../providers/account_providers.dart';
import '../providers/backup_providers.dart';
import '../providers/jobs_providers.dart';
import '../providers/providers.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/system_actions.dart';

enum _Outcome { running, ok, warn, fail }

/// One thing to check. [run] returns what it found, throws [_Warn] for "works,
/// but you may want to look", and throws anything else for a failure.
class _Check {
  _Check(this.name, this.run);

  final String name;
  final Future<String> Function() run;
  _Outcome outcome = _Outcome.running;
  String detail = '';
}

class _Warn implements Exception {
  const _Warn(this.message);
  final String message;
}

/// Settings › About › Self-check: tries the parts the app depends on (saved
/// settings, the database, secure storage, the job list, notifications, sign-in)
/// and shows what failed in plain words, with the real error to send along.
class SelfCheckScreen extends ConsumerStatefulWidget {
  const SelfCheckScreen({super.key});

  @override
  ConsumerState<SelfCheckScreen> createState() => _SelfCheckScreenState();
}

class _SelfCheckScreenState extends ConsumerState<SelfCheckScreen> {
  List<_Check> _checks = const [];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _runAll();
  }

  List<_Check> _build() => [
        _Check('App version', () async {
          final info = await PackageInfo.fromPlatform();
          return '${info.version} (build ${info.buildNumber})';
        }),
        _Check('Saved settings', () async {
          final prefs = await SharedPreferences.getInstance();
          final stamp = DateTime.now().microsecondsSinceEpoch.toString();
          await prefs.setString('selfcheck.ping', stamp);
          await prefs.reload();
          final back = prefs.getString('selfcheck.ping');
          await prefs.remove('selfcheck.ping');
          if (back != stamp) throw StateError('wrote $stamp, read back $back');
          return 'Read and write work · ${prefs.getKeys().length} saved values';
        }),
        _Check('Database', () async {
          final apps = await ref.read(databaseProvider).listApplications();
          return 'Opens · ${apps.length} tracked exams';
        }),
        _Check('Secure storage (portal passwords, PIN)', () async {
          final store = ref.read(secretStoreProvider);
          const id = '__selfcheck';
          await store.writePassword(id, 'ok');
          final back = await store.readPassword(id);
          await store.deletePassword(id);
          if (back != 'ok') throw StateError('read back $back');
          return 'Read and write work';
        }),
        for (final base in Env.dataBaseUrls)
          _Check('Job list from ${Uri.parse(base).host}', () async {
            final watch = Stopwatch()..start();
            final res = await http.get(Uri.parse('$base/jobs.json')).timeout(const Duration(seconds: 20));
            if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');
            final file = JobsFile.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
            final age = DateTime.now().difference(file.generatedAt);
            final note = '${file.jobs.length} jobs · updated ${_ago(age)} · ${watch.elapsedMilliseconds} ms';
            if (age > const Duration(days: 2)) throw _Warn('$note (older than 2 days)');
            return note;
          }),
        _Check('Jobs that fit you', () async {
          final snap = await ref.refresh(feedProvider.future);
          final shown = ref.read(rankedJobsProvider).length;
          final hidden = ref.read(hiddenJobsProvider).length;
          final profile = ref.read(profileProvider).dataOrNull;
          final note = '${snap.items.length} match your profile · $shown shown · $hidden hidden by your choices'
              '${snap.fromCache ? ' · from the saved copy' : ''}';
          if (profile == null) throw _Warn('No profile yet: $note');
          if (snap.items.isEmpty) throw _Warn(note);
          return note;
        }),
        _Check('Notifications', () async {
          final status = await Permission.notification.status;
          if (!status.isGranted) throw _Warn('Not allowed (${status.name}): no deadline reminders');
          return 'Allowed';
        }),
        _Check('Calendar', () async {
          final status = await Permission.calendarFullAccess.status;
          if (!status.isGranted) throw _Warn('Not allowed (${status.name}): only needed for calendar reminders');
          return 'Allowed';
        }),
        _Check('Google sign-in', () async {
          if (!Env.canSignIn) throw StateError('This build has no Google client ID');
          await GoogleAccountService.initialize();
          if (!ref.read(googleAccountServiceProvider).available) throw StateError('Google sign-in did not start');
          final user = ref.read(googleAccountProvider).dataOrNull;
          if (user == null) throw const _Warn('Ready · not signed in');
          return 'Signed in as ${user.email}';
        }),
        _Check('Drive backup', () async {
          final state = ref.read(backupControllerProvider);
          final at = state.lastBackupAt;
          if (ref.read(googleAccountProvider).dataOrNull == null) throw const _Warn('Sign in to back up');
          if (at == null) throw _Warn('Not backed up yet${state.message == null ? '' : ': ${state.message}'}');
          return 'Last backup ${_ago(DateTime.now().difference(at))}';
        }),
      ];

  static String _ago(Duration d) {
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} days ago';
  }

  Future<void> _runAll() async {
    final checks = _build();
    setState(() {
      _checks = checks;
      _running = true;
    });
    for (final c in checks) {
      try {
        c.detail = await c.run();
        c.outcome = _Outcome.ok;
      } on _Warn catch (w) {
        c.detail = w.message;
        c.outcome = _Outcome.warn;
      } catch (e) {
        final error = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
        c.detail = error.length <= 300 ? error : '${error.substring(0, 300)}…';
        c.outcome = _Outcome.fail;
      }
      if (!mounted) return;
      setState(() {});
    }
    if (mounted) setState(() => _running = false);
  }

  String get _report => [
        'JobSummit self-check ${DateTime.now().toIso8601String().substring(0, 16)}',
        for (final c in _checks) '${switch (c.outcome) {
          _Outcome.ok => '✓',
          _Outcome.warn => '!',
          _Outcome.fail => '✗',
          _Outcome.running => '…',
        }} ${c.name}: ${c.detail}',
      ].join('\n');

  @override
  Widget build(BuildContext context) {
    final colors = context.urgencyColors;
    final text = Theme.of(context).textTheme;
    final failed = _checks.where((c) => c.outcome == _Outcome.fail).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Self-check')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _running
                ? 'Checking…'
                : failed == 0
                    ? 'Everything the app needs is working.'
                    : '$failed ${failed == 1 ? 'thing isn’t' : 'things aren’t'} working. Copy the report and send it along.',
            style: text.titleMedium,
          ),
          const SizedBox(height: 12),
          for (final c in _checks)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: switch (c.outcome) {
                _Outcome.running => const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                _Outcome.ok => Icon(Icons.check_circle_rounded, color: colors.safe),
                _Outcome.warn => Icon(Icons.error_outline_rounded, color: colors.warning),
                _Outcome.fail => Icon(Icons.cancel_rounded, color: colors.urgent),
              },
              title: Text(c.name),
              subtitle: c.detail.isEmpty ? null : Text(c.detail),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: _running ? null : _runAll,
                child: const Text('Run again'),
              ),
              OutlinedButton(
                onPressed: _running
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: _report));
                        if (context.mounted) showCalmSnack(context, 'Report copied.');
                      },
                child: const Text('Copy report'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
