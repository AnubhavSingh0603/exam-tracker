import 'package:flutter/foundation.dart';

export 'qualification_taxonomy.g.dart';

/// Wire values match the backend's `QualificationLevel` enum.
@immutable
class QualificationLevel {
  const QualificationLevel(this.code, this.label, this.rank);

  final String code; // MATRIC … PHD
  final String label;
  final int rank;
}

@immutable
class DegreeOption {
  const DegreeOption(this.code, this.label, this.level, this.group, [this.implies]);

  final String code; // e.g. B_TECH
  final String label; // e.g. B.Tech / B.E.
  final String level; // QualificationLevel.code
  final String group; // picker heading

  /// The bachelor's every holder of this PG degree has (M_TECH -> B_TECH).
  final String? implies;
}
