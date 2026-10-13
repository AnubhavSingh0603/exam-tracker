import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'providers/providers.dart';
import 'screens/home_shell.dart';
import 'services/auth_service.dart';
import 'services/background_watch.dart';
import 'services/database_service.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'widgets/update_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  final db = await DatabaseService.open();
  try {
    await GoogleAccountService.initialize(); // Google sign-in for the Drive backup; no-op if not set up
  } catch (_) {
    // A misconfigured OAuth client must not stop the offline app from starting.
  }
  try {
    await NotificationService.init();
    await scheduleBackgroundWatch(); // exam watcher every ~4 h, even with the app closed
  } catch (_) {
    // Notifications/background work are extras: the app must still start without them.
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppPalette.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const ApplyTrackApp(),
  ));
}

class ApplyTrackApp extends StatelessWidget {
  const ApplyTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.darkPastel();
    return MaterialApp(
      title: 'ApplyTrack',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      home: const UpdateGate(child: HomeShell()),
    );
  }
}
