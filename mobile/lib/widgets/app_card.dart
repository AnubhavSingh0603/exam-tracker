import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Flat, bordered 16dp card. An optional [accent] draws a calm left stripe
/// instead of colouring the whole card.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.accent, this.padding = const EdgeInsets.all(16), this.onTap});

  final Widget child;
  final Color? accent;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.card);
    return Material(
      color: AppPalette.surface,
      shape: RoundedRectangleBorder(borderRadius: radius, side: const BorderSide(color: AppPalette.outline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: accent == null ? null : Border(left: BorderSide(color: accent!, width: 4)),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
