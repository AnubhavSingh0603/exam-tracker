import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

part 'app_icons.g.dart';

/// JobSummit's own icons (duotone: rounded lines plus a soft fill on the main
/// shape), tinted like an [Icon]: [color], else the surrounding [IconTheme].
class DuoIcon extends StatelessWidget {
  const DuoIcon(this.icon, {super.key, this.size, this.color, this.semanticLabel});

  final AppIcon icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  static final _svgs = {for (final e in _bodies.entries) e.key: '$_svgHead${e.value}</svg>'};

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    final c = color ?? theme.color ?? const Color(0xFF8B949E);
    return SvgPicture.string(
      _svgs[icon]!,
      width: s,
      height: s,
      theme: SvgTheme(currentColor: c),
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}

/// One of ours ([AppIcon]) or a plain Material symbol ([IconData]) for controls
/// like search, close and the expand arrows.
Widget glyph(Object icon, {double? size, Color? color}) => switch (icon) {
      final AppIcon i => DuoIcon(i, size: size, color: color),
      final IconData d => Icon(d, size: size, color: color),
      _ => throw ArgumentError.value(icon, 'icon', 'AppIcon or IconData'),
    };
