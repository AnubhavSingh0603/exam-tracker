import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../config/env.dart';

/// The home page with the download button: works for anyone, on any phone.
String get shareMessage => 'I use JobSummit to see only the government and PSU jobs I’m eligible for. '
    'It also keeps track of my exams: admit cards, exam dates, answer keys and results. '
    'Free, no ads: ${Env.homePageUrl}';

/// Opens Android's share sheet (WhatsApp, Telegram, Instagram, Gmail, SMS,
/// Nearby Share, copy…) with a short note and the download link.
Future<void> shareApp([SharePlus? share]) => (share ?? SharePlus.instance).share(
      ShareParams(text: shareMessage, subject: 'JobSummit: government jobs you can apply for', title: 'Share JobSummit'),
    );

class ShareAppButton extends StatelessWidget {
  const ShareAppButton({super.key, this.share});

  /// For tests; the real share sheet otherwise.
  final SharePlus? share;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: () => shareApp(share),
        icon: const Icon(Icons.share_rounded, size: 18),
        label: const Text('Share JobSummit with friends'),
      );
}
