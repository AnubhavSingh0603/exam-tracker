import 'package:flutter/material.dart';

import '../domain/urgency.dart';
import '../theme/app_theme.dart';
import 'app_icons.dart';


class CalmEmptyHero extends StatelessWidget {
  const CalmEmptyHero({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.urgencyColors;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.tint(Urgency.safe, 0.10),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Row(
        children: [
          DuoIcon(AppIcon.calmEmpty, color: colors.safe),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Nothing urgent right now. You are on track.', style: text.bodyLarge),
          ),
        ],
      ),
    );
  }
}
