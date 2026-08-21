/// Which calendar week a Weekly Planner row belongs to.
///
/// `user_meal_plans.week_start` is the **Monday** of the plan's week, stored as
/// a `date`. Before migration `20260822120000` there was no such column: day 0
/// meant "Monday, whichever Monday you happen to be looking at", so nothing
/// ever rolled over, and the this-week/next-week toggle had to encode next week
/// as `day_index + 7`. Both of those are gone.
///
/// The week the user is looking at is **computed at read time**, never stored
/// as app state: "this week" is [plannerWeekStartFor] of now, "next week" is
/// [plannerWeekAfter] of that. Rollover therefore happens by itself, at
/// midnight on Sunday, with nothing to advance and nothing to migrate weekly.
/// Weeks that fall behind simply stop being asked for — the rows stay (this is
/// not a delete), there is just no way to navigate to them, by design. History
/// lives in My recipes and the Waste Ledger.
///
/// **Boundary: Monday, device-local time** (Harris's ruling, 2026-08-22). Not
/// pinned to Europe/Zurich: a travelling user's "this week" should follow the
/// phone in their pocket, and a fixed zone would roll their planner over at the
/// wrong hour. The Swiss default falls out of the device being in Switzerland,
/// which is the same answer without the special case. The one asymmetry worth
/// knowing: the migration's *backfill* did compute Zurich's Monday, because a
/// migration has no device to ask.
library;

/// The Monday of [date]'s week, as a date-only local `DateTime`.
///
/// Built through the `DateTime` constructor rather than `subtract(Duration)`
/// on purpose: `Duration` arithmetic is absolute-time arithmetic, so crossing a
/// DST change can land on 23:00 of the previous day and silently move the whole
/// week. The constructor normalizes out-of-range day values (day 0 is the last
/// day of the previous month, day -3 is three days before that) and stays on
/// calendar days.
DateTime plannerWeekStartFor(DateTime date) {
  final daysSinceMonday = date.weekday - DateTime.monday;
  return DateTime(date.year, date.month, date.day - daysSinceMonday);
}

/// The Monday one week after [weekStart]. Same DST reasoning as above.
DateTime plannerWeekAfter(DateTime weekStart) =>
    DateTime(weekStart.year, weekStart.month, weekStart.day + 7);

/// `yyyy-MM-dd` — exactly what the `date` column stores and what PostgREST
/// filters on. This is the app's canonical representation of a week: it is
/// what travels in `PlannerSlotRef`, so week identity compares as plain string
/// equality and cannot pick up a stray time component.
String plannerWeekValue(DateTime weekStart) {
  final month = weekStart.month.toString().padLeft(2, '0');
  final day = weekStart.day.toString().padLeft(2, '0');
  return '${weekStart.year.toString().padLeft(4, '0')}-$month-$day';
}

/// Convenience: the `week_start` value for the week containing [date].
String plannerWeekValueFor(DateTime date) =>
    plannerWeekValue(plannerWeekStartFor(date));
