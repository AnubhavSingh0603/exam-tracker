import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/fx.dart';

const _sensitiveClearAfter = Duration(seconds: 45);

/// A failure: the gentle error sound, then the same calm message.
void showErrorSnack(BuildContext context, String message) {
  Fx.error();
  showCalmSnack(context, message);
}

void showCalmSnack(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action, duration: const Duration(seconds: 4)));
}

/// Copies [value]. Sensitive values are wiped from the clipboard after 45 s,
/// but only if the user hasn't copied something else in the meantime.
const _clipboard = MethodChannel('jobsummit/clipboard');

Future<void> copyToClipboard(BuildContext context, String label, String value, {bool sensitive = false}) async {
  if (sensitive) {
    // Marked sensitive (no preview, kept out of keyboard clipboard history); a plain
    // copy where that isn't available (tests, other platforms).
    try {
      await _clipboard.invokeMethod<void>('copySensitive', {'text': value});
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: value));
    }
  } else {
    await Clipboard.setData(ClipboardData(text: value));
  }
  Fx.copy();
  if (sensitive) {
    Timer(_sensitiveClearAfter, () async {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == value) await Clipboard.setData(const ClipboardData(text: ''));
    });
  }
  if (!context.mounted) return;
  showCalmSnack(context, sensitive ? '$label copied — clears in 45 s' : '$label copied');
}

/// Opens [url] in the browser/app that owns it (exam portals often break in
/// in-app web views because of captchas and downloads).
Future<void> openExternal(BuildContext context, String? url) async {
  final uri = url == null ? null : Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    showCalmSnack(context, 'No portal link saved for this one.');
    return;
  }
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showErrorSnack(context, 'Could not open the link.');
}
