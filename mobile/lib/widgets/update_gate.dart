import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'update_dialog.dart';

/// Checks for updates after the first frame and whenever the app returns to the
/// foreground (the service itself throttles to once per 12 h). Never blocks startup.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> with WidgetsBindingObserver {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_showing) return;
    final service = ref.read(updateServiceProvider);
    final update = await service.check();
    if (update == null || !mounted) return;
    _showing = true;
    await showUpdateDialog(context, service, update);
    _showing = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
