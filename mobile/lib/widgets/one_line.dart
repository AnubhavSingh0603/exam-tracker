import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A label that never wraps or splits a word: with big phone text it shrinks a
/// little to fit its space instead ("Sync to Cal / endar" can't happen).
class OneLine extends StatelessWidget {
  const OneLine(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, style: style, maxLines: 1, softWrap: false),
      );
}

/// "For you 226": a one-line label with its count in a small badge.
class CountLabel extends StatelessWidget {
  const CountLabel(this.label, this.count, {super.key});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.labelSmall;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, maxLines: 1, softWrap: false),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: AppPalette.outline.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('$count', maxLines: 1, softWrap: false, style: small?.copyWith(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
