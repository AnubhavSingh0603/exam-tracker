import 'package:flutter/material.dart';

import '../services/fx.dart';
import '../theme/app_theme.dart';

/// A small two- or three-way switch in a pill: "Overview | Focus", "Week | Month".
/// Labels stay on one line (they shrink a little with very large text).
class PillToggle<T> extends StatelessWidget {
  const PillToggle({super.key, required this.options, required this.selected, required this.onChanged});

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppPalette.surface, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, label) in options)
            Semantics(
              button: true,
              selected: value == selected,
              child: Material(
                color: value == selected ? AppPalette.surfaceVariant : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: value == selected
                      ? null
                      : () {
                          Fx.tap();
                          onChanged(value);
                        },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        widthFactor: 1,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            maxLines: 1,
                            softWrap: false,
                            style: style?.copyWith(
                              color: value == selected ? AppPalette.textPrimary : AppPalette.textMuted,
                              fontWeight: value == selected ? FontWeight.w900 : FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
