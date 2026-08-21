import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:optimeal/data/cooking_times.dart';

/// Parity between `lib/data/cooking_times.dart` and the committed
/// `docs/cooking_times_table.md`, which is the transcription of Chef Harris's
/// signed paper worksheet and the single source of truth for every figure.
///
/// The Dart file is DERIVED from the doc. This test re-parses the doc from
/// scratch — deliberately with its own parser, not a shared helper — and
/// asserts row count, the exact key set, every band and every numeric minute.
/// If someone hand-edits a band in Dart, or edits the doc without re-deriving,
/// the build fails here rather than silently shipping two different tables.
void main() {
  final doc = _parseDoc();

  group('cooking times table parity', () {
    test('row count matches the doc, per section', () {
      expect(doc.length, 74, reason: 'doc should hold 74 rows');
      expect(CookingTimes.rows.length, doc.length);

      int docCount(CookingTimeSection s) => doc.where((r) => r.section == s).length;
      int dartCount(CookingTimeSection s) =>
          CookingTimes.rows.where((r) => r.section == s).length;

      for (final s in CookingTimeSection.values) {
        expect(dartCount(s), docCount(s), reason: 'section ${s.name}');
      }
      expect(docCount(CookingTimeSection.vegetables), 42);
      expect(docCount(CookingTimeSection.proteins), 21);
      expect(docCount(CookingTimeSection.starches), 11);
    });

    test('key set matches exactly, in doc order', () {
      expect(
        CookingTimes.rows.map((r) => r.key).toList(),
        doc.map((r) => r.key).toList(),
      );
    });

    test('every row: band(s), minutes and section match the doc', () {
      for (final expected in doc) {
        final actual = CookingTimes.row(expected.key);
        expect(actual, isNotNull, reason: 'missing key ${expected.key}');

        expect(
          actual!.bands.map((b) => b.label).toList(),
          expected.bands,
          reason: 'bands for ${expected.key}',
        );
        expect(actual.minutes, expected.minutes,
            reason: 'minutes for ${expected.key}');
        expect(actual.section, expected.section,
            reason: 'section for ${expected.key}');
      }
    });

    test('the two exceptional rows are exactly the ones the doc marks', () {
      // Every other row carries exactly one band. If a third row ever becomes
      // dual-band or pending, that is a product decision, not a silent change.
      final notSingleBand =
          CookingTimes.rows.where((r) => r.bands.length != 1).map((r) => r.key).toSet();
      expect(notSingleBand, {'lamb_diced_2cm_dice', 'red_lentils_simmer'});

      expect(CookingTimes.row('lamb_diced_2cm_dice')!.bands,
          [CookBand.b3, CookBand.b6]);
      expect(CookingTimes.row('red_lentils_simmer')!.bandPending, isTrue);
      expect(CookingTimes.row('red_lentils_simmer')!.bands, isEmpty);
      expect(CookingTimes.rows.where((r) => r.bandPending).length, 1);
    });

    test('the three package-instruction rows are marked advisory, and only those', () {
      final advisory =
          CookingTimes.rows.where((r) => r.minutesAdvisory).map((r) => r.key).toSet();
      expect(advisory, {'dried_pasta', 'white_rice_absorption', 'brown_rice_absorption'});
    });

    test('density classes are carried on vegetables only, as in the doc', () {
      for (final r in CookingTimes.rows) {
        expect(
          r.densityClass != null,
          r.section == CookingTimeSection.vegetables,
          reason: r.key,
        );
      }
    });
  });
}

class _DocRow {
  _DocRow(this.key, this.section, this.bands, this.minutes);
  final String key;
  final CookingTimeSection section;
  final List<String> bands;
  final Map<String, int> minutes;
}

String _clean(String cell) => cell.replaceAll(RegExp(r'[*`]'), '').trim();

int? _minutes(String cell) {
  final c = _clean(cell);
  if (c.contains('pending')) return null;
  final m = RegExp(r'(\d+)').firstMatch(c);
  return m == null ? null : int.parse(m.group(1)!);
}

List<String> _bands(String cell) {
  final c = _clean(cell);
  if (c.contains('pending')) return const [];
  return RegExp(r'B[1-6]').allMatches(c).map((m) => m.group(0)!).toList();
}

List<List<String>> _tableRows(String md, String from, String to) {
  final a = md.indexOf(from);
  final b = md.indexOf(to, a);
  if (a < 0) throw StateError('section "$from" not found in the doc');
  if (b <= a) throw StateError('section "$to" not found in the doc');
  return md
      .substring(a, b)
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.startsWith('| `'))
      .map((l) => l.substring(1, l.length - 1).split('|').map((c) => c.trim()).toList())
      .toList();
}

List<_DocRow> _parseDoc() {
  final file = File('docs/cooking_times_table.md');
  if (!file.existsSync()) {
    throw StateError(
        'the signed table doc must stay committed at docs/cooking_times_table.md');
  }
  final md = file.readAsStringSync();

  Map<String, int> mins(List<String> names, List<int?> raw) => {
        for (var i = 0; i < names.length; i++)
          if (raw[i] != null) names[i]: raw[i]!,
      };

  return [
    for (final r in _tableRows(md, '## 4. Vegetables', '## 5. Proteins'))
      _DocRow(
        _clean(r[0]),
        CookingTimeSection.vegetables,
        _bands(r[8]),
        mins(const ['saute', 'roast', 'boil', 'steam'],
            [_minutes(r[4]), _minutes(r[5]), _minutes(r[6]), _minutes(r[7])]),
      ),
    for (final r in _tableRows(md, '## 5. Proteins', '## 6. Starches'))
      _DocRow(
        _clean(r[0]),
        CookingTimeSection.proteins,
        _bands(r[6]),
        mins(const ['pan', 'roast', 'simmer'],
            [_minutes(r[3]), _minutes(r[4]), _minutes(r[5])]),
      ),
    for (final r in _tableRows(md, '## 6. Starches', "**Harris's ruling"))
      _DocRow(
        _clean(r[0]),
        CookingTimeSection.starches,
        _bands(r[4]),
        mins(const ['time'], [_minutes(r[3])]),
      ),
  ];
}
