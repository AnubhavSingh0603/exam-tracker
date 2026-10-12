import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'providers/providers.dart';
import 'screens/dashboard_screen.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'theme/app_theme.dart';
import 'widgets/update_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  final db = await DatabaseService.open();
  try {
    await AuthService.initialize(); // Google sign-in; no-op if this build isn't configured for it
  } catch (_) {
    // A misconfigured OAuth client must not stop the offline app from starting.
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppPalette.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const ExamTrackerApp(),
  ));
}

class ExamTrackerApp extends StatelessWidget {
  const ExamTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.darkPastel();
    return MaterialApp(
      title: 'Exam Tracker',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      home: const UpdateGate(child: DashboardScreen()),
    );
  }
}
