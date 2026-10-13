import 'package:flutter/material.dart';

import '../domain/lifecycle.dart';
import '../models/tracked_application.dart';
import '../theme/app_theme.dart';
import '../utils/system_actions.dart';
import 'app_icons.dart';

/// Vertical 5-stage timeline: Applied → Admit card → Exam → Answer key → Result.
/// Completed sage, active terracotta, upcoming honey, locked grey. Each stage
/// shows its date and one-tap links (download admit card, answer key, result).
class ExamLifecycleStepper extends StatelessWidget {
  const ExamLifecycleStepper({super.key, required this.app, required this.now});

  final TrackedApplication app;
  final DateTime now;

  static Color colorOf(StageState s) => switch (s) {
        StageState.completed => AppPalette.sage,
        StageState.active => AppPalette.terracotta,
        StageState.upcoming => AppPalette.honey,
        StageState.locked => AppPalette.textMuted,
      };

  @override
  Widget build(BuildContext context) {
    final stages = computeLifecycle(app, app.timeline, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < stages.length; i++) _StageRow(view: stages[i], isLast: i == stages.length - 1),
      ],
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({required this.view, required this.isLast});

  final StageView view;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = ExamLifecycleStepper.colorOf(view.state);
    final date = view.date;
    final stateLabel = switch (view.state) {
      StageState.completed => 'done',
      StageState.active => 'now',
      StageState.upcoming => 'next',
      StageState.locked => 'not announced yet',
    };
    final muted = view.state == StageState.locked;

    return Semantics(
      label:
          '${view.stage.label}, $stateLabel${date == null ? '' : ', ${stageDateLabel(date, view.dateEnd)}'}',
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Rail: dot + connector.
            SizedBox(
              width: 24,
              child: Column(
                children: [
                  const SizedBox(height: 2),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: view.state == StageState.locked ? Colors.transparent : color,
                      border: Border.all(color: color, width: 2),
                    ),
                    child: view.state == StageState.completed
                        ? Icon(Icons.check_rounded, size: 10, color: AppPalette.background)
                        : null,
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(width: 2, color: color.withValues(alpha: 0.35)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            view.stage.label,
                            style: text.titleSmall?.copyWith(color: muted ? AppPalette.textMuted : null),
                          ),
                        ),
                        if (date != null)
                          Text(stageDateLabel(date, view.dateEnd),
                              style: text.labelMedium?.copyWith(color: color)),
                      ],
                    ),
                    for (final d in view.details) ...[
                      const SizedBox(height: 2),
                      Text(d, style: text.bodySmall),
                    ],
                    if (view.actions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final a in view.actions)
                            a.primary
                                ? FilledButton.tonalIcon(
                                    onPressed: () => openExternal(context, a.url),
                                    icon: const DuoIcon(AppIcon.applyOnline, size: 16),
                                    label: Text(a.label),
                                  )
                                : TextButton(
                                    onPressed: () => openExternal(context, a.url),
                                    child: Text(a.label),
                                  ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
