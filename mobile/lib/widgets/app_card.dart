import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A solid, raised tile: a face tinted with its [accent] colour (urgency: coral for
/// the last days, amber soon, mint when safe; the app's violet without one) on a
/// deeper "3D" base of the same colour, with a soft coloured shadow. No outlines:
/// colour alone sets cards apart from the background and from each other.
///
/// Pressing it sinks the face onto its base like a physical button (instant, with
/// no movement, when "Remove animations" is on).
class AppCard extends StatefulWidget {
  const AppCard({super.key, required this.child, this.accent, this.padding = const EdgeInsets.all(16), this.onTap});

  final Widget child;
  final Color? accent;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// How far the face stands above its base.
  static const depth = 5.0;

  /// Card colours for [accent] on the current palette: (face, base).
  static (Color, Color) colorsFor(Color? accent) {
    final light = AppPalette.current == Palette.light;
    final tint = accent ?? AppPalette.periwinkle;
    final face = Color.alphaBlend(tint.withValues(alpha: light ? 0.17 : 0.25), AppPalette.surface);
    final base = Color.alphaBlend(tint.withValues(alpha: light ? 0.55 : 0.62), AppPalette.surface);
    return (face, base);
  }

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
        // The base: the face sits on it, [depth] above; pressing closes the gap.
        padding: EdgeInsets.only(bottom: AppCard.depth - sink),
        margin: EdgeInsets.only(top: sink),
        decoration: BoxDecoration(
          color: base,
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: (widget.accent ?? AppPalette.periwinkle).withValues(alpha: _down ? 0.10 : 0.22),
              blurRadius: _down ? 8 : 18,
              offset: Offset(0, _down ? 3 : 9),
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
