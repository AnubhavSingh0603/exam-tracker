import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/app_theme.dart';

/// Samsung puts apps that haven't been opened for a few days to sleep, and a sleeping
/// app can't run its background checks (dontkillmyapp.com/samsung). No code can opt
/// out of it: the user has to tell the phone, once.
Future<bool> isSamsungPhone() async {
  if (!Platform.isAndroid) return false;
  try {
    return (await DeviceInfoPlugin().androidInfo).manufacturer.toLowerCase() == 'samsung';
  } catch (_) {
    return false;
  }
}

Future<void> showSamsungSleepTip(BuildContext context) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppPalette.surface,
        title: const Text('Keep exam alerts on time'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Samsung phones put apps to sleep after a few days without use, which pauses '
                'exam checks. Two settings stop that:'),
            SizedBox(height: 12),
            _Step(1, 'App settings → Battery → Unrestricted'),
            SizedBox(height: 8),
            _Step(2, 'Settings → Battery → Background usage limits → Never sleeping apps → add JobSummit'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          const FilledButton(onPressed: openAppSettings, child: Text('Open app settings')),
        ],
      ),
    );

class _Step extends StatelessWidget {
  const _Step(this.number, this.text);

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: AppPalette.periwinkle.withValues(alpha: 0.2),
            child: Text('$number', style: Theme.of(context).textTheme.labelSmall),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      );
}
