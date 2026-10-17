import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import '../../widgets/summit_backdrop.dart';
import 'private_applications_screen.dart';
import 'private_jobs_screen.dart';
import 'private_profile_page.dart';

/// The Private workspace: its own roles, its own application pipeline and its own
/// profile, in its own colours. The Govt | Private switch sits on Roles.
class PrivateShell extends StatefulWidget {
  const PrivateShell({super.key});

  @override
  State<PrivateShell> createState() => _PrivateShellState();
}

class _PrivateShellState extends State<PrivateShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppPalette.background,
        body: Stack(
          children: [
            Positioned.fill(child: SummitBackdrop(height: SummitHeights.privateTabs[_tab])),
            SafeArea(
              bottom: false,
              child: TabSwitcher(
                index: _tab,
                children: const [PrivateJobsScreen(), PrivateApplicationsScreen(), _ProfileTab()],
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          backgroundColor: AppPalette.surface,
          indicatorColor: AppPalette.periwinkle.withValues(alpha: 0.22),
          destinations: const [
            NavigationDestination(icon: DuoIcon(AppIcon.experience), label: 'Roles'),
            NavigationDestination(icon: DuoIcon(AppIcon.applied), label: 'Applications'),
            NavigationDestination(icon: DuoIcon(AppIcon.profile), label: 'Profile'),
          ],
        ),
      );
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ScreenHeader(title: 'Profile', subtitle: 'Private · separate from your Govt profile'),
          ),
          SizedBox(height: 70), // the mountain shows here
          Expanded(child: PrivateProfilePage()),
        ],
      );
}
