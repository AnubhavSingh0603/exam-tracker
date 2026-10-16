import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'features/private_jobs/private_jobs.dart';
import 'providers/providers.dart';
import 'providers/ui_providers.dart';
import 'providers/workspace_providers.dart';
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
    await db.encryptStoredIds(); // Reg/Roll numbers saved before they were encrypted
  } catch (_) {
    // Stays readable as it was; tried again at the next start.
  }
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

  final themeMode = await ThemeModeNotifier.load();

  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      themeModeProvider.overrideWith(() => ThemeModeNotifier(themeMode)),
    ],
    child: const JobSummitApp(),
  ));
}

class JobSummitApp extends ConsumerWidget {
  const JobSummitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
        title: 'JobSummit',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.of(Brightness.light),
        darkTheme: AppTheme.of(Brightness.dark),
        themeMode: ref.watch(themeModeProvider),
        builder: (context, child) => _PaletteScope(brightness: Theme.of(context).brightness, child: child!),
        // The one place the app knows about the optional Private workspace.
        home: UpdateGate(
          child: ref.watch(workspaceProvider).shown == Workspace.private ? const PrivateShell() : const HomeShell(),
        ),
      );
}

/// Points [AppPalette] at the light or dark colours before anything below builds,
/// and repaints every screen (keeping its state) when that changes.
class _PaletteScope extends StatefulWidget {
  const _PaletteScope({required this.brightness, required this.child});

  final Brightness brightness;
  final Widget child;

  @override
  State<_PaletteScope> createState() => _PaletteScopeState();
}

class _PaletteScopeState extends State<_PaletteScope> {
  Brightness? _applied;

  static void _rebuildAll(Element element) {
    element.markNeedsBuild();
    element.visitChildren(_rebuildAll);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.brightness;
    if (_applied != b) {
      final first = _applied == null;
      _applied = b;
      AppPalette.use(b);
      final light = b == Brightness.light;
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: AppPalette.background,
        systemNavigationBarIconBrightness: light ? Brightness.dark : Brightness.light,
      ));
      if (!first) {
        // Widgets that read AppPalette directly don't depend on the Theme: mark them all.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) (context as Element).visitChildren(_rebuildAll);
        });
      }
    }
    return widget.child;
  }
}
