import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/models/planner_week.dart';

/// Week anchoring (migration `20260822120000`). The boundary is **Monday,
/// device-local time** — Harris's ruling, 2026-08-22: a travelling user's "this
/// week" should follow the phone in their pocket, so this is deliberately not
/// pinned to Europe/Zurich.

void main() {
  group('the Monday boundary', () {
    test('Sunday still belongs to the week that began the previous Monday', () {
      // 2026-08-30 is a Sunday, 23:59 local.
      expect(
        plannerWeekStartFor(DateTime(2026, 8, 30, 23, 59, 59)),
        DateTime(2026, 8, 24),
      );
    });

    test('one minute later, Monday starts a new week', () {
      expect(
        plannerWeekStartFor(DateTime(2026, 8, 31, 0, 0, 0)),
        DateTime(2026, 8, 31),
      );
    });

    test('every day of one week resolves to the same Monday', () {
      for (var day = 24; day <= 30; day++) {
        expect(
          plannerWeekStartFor(DateTime(2026, 8, day, 13, 37)),
          DateTime(2026, 8, 24),
          reason: '2026-08-$day',
        );
      }
    });

    test('a Monday is its own week start, at any hour', () {
      expect(plannerWeekStartFor(DateTime(2026, 8, 24)), DateTime(2026, 8, 24));
      expect(plannerWeekStartFor(DateTime(2026, 8, 24, 23, 59)),
          DateTime(2026, 8, 24));
    });

    test('the week start crosses a month boundary without arithmetic damage',
        () {
      // 2026-09-02 is a Wednesday; its Monday is in August.
      expect(plannerWeekStartFor(DateTime(2026, 9, 2)), DateTime(2026, 8, 31));
      // 2027-01-01 is a Friday; its Monday is in the previous year.
      expect(plannerWeekStartFor(DateTime(2027, 1, 1)), DateTime(2026, 12, 28));
    });

    test('the returned week start carries no time component', () {
      final start = plannerWeekStartFor(DateTime(2026, 8, 26, 17, 42, 11, 999));
      expect(start.hour, 0);
      expect(start.minute, 0);
      expect(start.second, 0);
      expect(start.millisecond, 0);
    });
  });

  group('next week', () {
    test('is exactly seven calendar days on', () {
      expect(plannerWeekAfter(DateTime(2026, 8, 24)), DateTime(2026, 8, 31));
    });

    test('crosses months and years as calendar days, not 168 hours', () {
      // Both of these would drift by an hour under Duration arithmetic across
      // a DST change, which is why the constructor is used instead.
      expect(plannerWeekAfter(DateTime(2026, 10, 19)), DateTime(2026, 10, 26));
      expect(plannerWeekAfter(DateTime(2026, 12, 28)), DateTime(2027, 1, 4));
    });
  });

  group('the stored value', () {
    test('is the zero-padded yyyy-MM-dd the date column holds', () {
      expect(plannerWeekValue(DateTime(2026, 8, 31)), '2026-08-31');
      expect(plannerWeekValue(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('ignores any time on the DateTime it is given', () {
      expect(plannerWeekValueFor(DateTime(2026, 8, 26, 23, 59)), '2026-08-24');
    });
  });
}
