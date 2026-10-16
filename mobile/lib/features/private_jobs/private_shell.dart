import 'package:flutter/material.dart';

import '../../widgets/app_icons.dart';
import 'private_applications_screen.dart';
import 'private_jobs_screen.dart';

/// The Private workspace: its own feed and its own application tracker. The Govt |
/// Private switch sits at the top of each screen.
class PrivateShell extends StatefulWidget {
  const PrivateShell({super.key});

  @override
  State<PrivateShell> createState() => _PrivateShellState();
}

class _PrivateShellState extends State<PrivateShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _tab,
            children: const [PrivateJobsScreen(), PrivateApplicationsScreen()],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: DuoIcon(AppIcon.experience), label: 'Jobs'),
            NavigationDestination(icon: DuoIcon(AppIcon.applied), label: 'Applications'),
          ],
        ),
      );
}
