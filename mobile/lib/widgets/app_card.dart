import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A solid, raised tile: a plain face on a deeper "3D" edge, with a soft shadow.
/// No outlines and no tint: cards stand apart by their solid face alone, and colour
/// stays in the small things on them (deadline pills, category tags, buttons).
///
/// Pressing it sinks the face onto its edge like a physical button (instant, with
/// no movement, when "Remove animations" is on).
class AppCard extends StatefulWidget {
  const AppCard({super.key, required this.child, this.accent, this.padding = const EdgeInsets.all(16), this.onTap});

  final Widget child;

  /// Only colours the tap ripple now (cards are no longer tinted).
  final Color? accent;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// How far the face stands above its edge.
  static const depth = 5.0;

  /// Card colours on the current palette: (face, edge).
  static (Color, Color) colorsFor(Color? accent) => (AppPalette.surface, AppPalette.cardBase);

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _down = false;

  void _press(bool down) {
    if (widget.onTap != null && _down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.card);
    final (face, base) = AppCard.colorsFor(widget.accent);
    final light = AppPalette.current.isLight;
    final still = MediaQuery.of(context).disableAnimations;
    final sink = _down ? AppCard.depth - 1 : 0.0;
    final duration = still ? Duration.zero : const Duration(milliseconds: 90);

    return Listener(
      onPointerDown: (_) => _press(true),
      onPointerUp: (_) => _press(false),
      onPointerCancel: (_) => _press(false),
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOut,
        // The edge: the face sits on it, [depth] above; pressing closes the gap.
        padding: EdgeInsets.only(bottom: AppCard.depth - sink),
        margin: EdgeInsets.only(top: sink),
        decoration: BoxDecoration(
          color: base,
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: light ? (_down ? 0.03 : 0.06) : (_down ? 0.12 : 0.24)),
              blurRadius: _down ? 6 : 14,
              offset: Offset(0, _down ? 2 : 6),
            ),
          ],
        ),
        child: Material(
          color: face,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            splashColor: (widget.accent ?? AppPalette.periwinkle).withValues(alpha: 0.12),
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}
