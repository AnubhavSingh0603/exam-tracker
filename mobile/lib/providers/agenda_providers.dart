import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/agenda.dart';
import 'jobs_providers.dart';
import 'providers.dart';

/// Everything dated, soonest first: last days of the jobs that fit you and the
/// dates of the exams you track.
final agendaProvider = Provider<List<AgendaItem>>((ref) => buildAgenda(
      tracked: ref.watch(activeAppsProvider),
      jobs: [for (final r in ref.watch(rankedJobsProvider)) r.item],
      now: ref.watch(nowProvider),
    ));

enum AgendaView { week, month }

/// Week or Month, kept while the app is open.
class AgendaViewNotifier extends Notifier<AgendaView> {
  @override
  AgendaView build() => AgendaView.week;

  void show(AgendaView view) => state = view;
}

final agendaViewProvider = NotifierProvider<AgendaViewNotifier, AgendaView>(AgendaViewNotifier.new);
