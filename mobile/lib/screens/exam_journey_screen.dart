import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tracked_application.dart';
import '../providers/providers.dart';
import '../widgets/common.dart';
import '../widgets/exam_journey_view.dart';

/// One tracked exam on its own page: tap an exam anywhere (My exams, Agenda) to
/// get here. Follows the live data, so status changes show at once.
class ExamJourneyScreen extends ConsumerWidget {
  const ExamJourneyScreen({super.key, required this.appId});

  final String appId;

  static Future<void> open(BuildContext context, TrackedApplication app) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => ExamJourneyScreen(appId: app.id)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final now = ref.watch(nowProvider);
    final app = ref.watch(trackedAppsProvider).dataOrNull?.where((a) => a.id == appId).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: app == null
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app.postName, style: text.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (app.examName != app.postName)
                    Text(app.examName, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
      ),
      body: app == null
          ? const Padding(padding: EdgeInsets.all(24), child: MutedNote('This exam isn’t tracked any more.'))
          : RefreshIndicator(
              onRefresh: () => ref.read(trackedAppsProvider.notifier).checkForUpdates(force: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [ExamJourneyView(app: app, now: now)],
              ),
            ),
    );
  }
}
