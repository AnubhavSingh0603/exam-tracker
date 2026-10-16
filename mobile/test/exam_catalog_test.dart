import 'package:exam_tracker/domain/exam_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<String> names(String q) => [for (final e in suggestExams(q)) e.name];

  test('typing a board lists its exams, names starting with it first', () {
    expect(names('SSC').take(4), ['SSC CGL', 'SSC CHSL', 'SSC MTS', 'SSC JE']);
  });

  test('years and cycle numerals are ignored when searching', () {
    expect(names('ibps po xv').first, 'IBPS PO');
    expect(names('CRP PO/MT-XV').first, 'IBPS PO');
    expect(names('cgl 2026').first, 'SSC CGL');
  });

  test('a numeral after "Scale" names the post, not the cycle', () {
    expect(names('officer scale ii').first, 'IBPS RRB Officer Scale II');
    expect(names('officer scale i').first, 'IBPS RRB PO');
  });

  test('aliases find exams by their long names', () {
    expect(names('combined graduate').first, 'SSC CGL');
    expect(names('assistant loco').first, 'RRB ALP');
  });

  test('the saved name carries the round: typed, else this year', () {
    final po = examCatalog.firstWhere((e) => e.id == 'ibps-po');
    final cgl = examCatalog.firstWhere((e) => e.id == 'ssc-cgl');
    final now = DateTime(2026, 10, 16);
    expect(trackedNameFor(po, 'ibps po xv', now), 'IBPS PO XV');
    expect(trackedNameFor(cgl, 'cgl', now), 'SSC CGL 2026');
    expect(trackedNameFor(cgl, 'cgl 2025', now), 'SSC CGL 2025');
  });

  test('matching a tracked exam needs the board too, so look-alike posts stay unmatched', () {
    expect(matchCatalogExam('Combined Graduate Level Examination 2026 Staff Selection Commission')?.id, 'ssc-cgl');
    expect(matchCatalogExam('IBPS CRP RRBs-XIV Officer Scale-II')?.id, 'ibps-rrb-scale-2');
    expect(matchCatalogExam('Office Assistant Allahabad High Court'), isNull);
    expect(matchCatalogExam('NTPC Limited Executive Trainee'), isNull);
  });

  test('every exam has a https website and at least one stage', () {
    for (final e in examCatalog) {
      expect(e.officialUrl, startsWith('https://'), reason: e.id);
      if (e.loginUrl != null) expect(e.loginUrl, startsWith('https://'), reason: e.id);
      expect(e.stages, isNotEmpty, reason: e.id);
    }
    expect({for (final e in examCatalog) e.id}.length, examCatalog.length, reason: 'ids are unique');
  });
}
