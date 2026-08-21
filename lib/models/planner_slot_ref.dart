/// Which Weekly Planner slot a Cook Mode session was launched from.
///
/// **Launch context, not recipe data** — the same distinction [RecipeOrigin]
/// draws from the other side. Where a recipe *came from* is a property of the
/// recipe and travels inside `CookModeRecipePayload`; which planner row the
/// user pressed Cook on is a property of *this launch* and travels beside it,
/// on `CookModeLaunchRequest` and on the saved active session. It is
/// deliberately NOT a field on `CookModeRecipePayload`: that payload is
/// persisted into `saved_recipes.recipe_payload` and
/// `user_meal_plans.recipe_payload`, and a saved recipe that permanently
/// remembered "Tuesday, slot 1" would mark the wrong row the next time it was
/// cooked from anywhere.
///
/// This exists because a finished cook could not be attributed to a planner
/// day slot at all (CLAUDE.md roadmap item 27, ruling: option A). The
/// alternatives were all inference — matching the cook log by recipe title,
/// which is ambiguous the moment the same dish is planned on two days, and
/// which would also mark a planner slot for a cook launched from Home.
/// **Nothing infers this value.** A cook launched from anywhere other than a
/// planner row carries null, and null means "no planner row was cooked".
class PlannerSlotRef {
  const PlannerSlotRef({
    required this.weekStart,
    required this.dayIndex,
    required this.slotIndex,
  });

  /// `yyyy-MM-dd` Monday, matching `user_meal_plans.week_start` — see
  /// `plannerWeekValue`. Part of the slot's identity since migration
  /// `20260822120000`: without it a cook finished after midnight on Sunday
  /// would mark the *new* week's Tuesday, because `(day, slot)` alone stopped
  /// being unique the moment weeks were anchored to dates. Carried as the
  /// stored string rather than a `DateTime` so week identity is plain string
  /// equality and can never pick up a stray time component.
  final String weekStart;

  /// Monday-based day of the week, 0–6, matching `user_meal_plans.day_index`.
  final int dayIndex;

  /// 0-based position within the day, matching `user_meal_plans.slot_index`.
  final int slotIndex;

  Map<String, dynamic> toJson() => {
        'weekStart': weekStart,
        'dayIndex': dayIndex,
        'slotIndex': slotIndex,
      };

  /// Tolerant by design: this is read back out of a locally persisted active
  /// cook session, which may have been written by an older build that had no
  /// such field at all. Anything unusable reads as "no slot", which is the
  /// safe answer — it attributes nothing rather than attributing wrongly.
  static PlannerSlotRef? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final week = '${raw['weekStart'] ?? raw['week_start'] ?? ''}'.trim();
    final day = int.tryParse('${raw['dayIndex'] ?? raw['day_index'] ?? ''}'.trim());
    final slot = int.tryParse('${raw['slotIndex'] ?? raw['slot_index'] ?? ''}'.trim());
    if (day == null || slot == null) return null;
    if (day < 0 || slot < 0) return null;
    // A session saved before week anchoring has no week, and there is no
    // honest way to invent one — the plan it belonged to may since have rolled
    // over. Read as "no slot", which attributes nothing.
    if (week.isEmpty) return null;
    return PlannerSlotRef(weekStart: week, dayIndex: day, slotIndex: slot);
  }

  @override
  bool operator ==(Object other) =>
      other is PlannerSlotRef &&
      other.weekStart == weekStart &&
      other.dayIndex == dayIndex &&
      other.slotIndex == slotIndex;

  @override
  int get hashCode => Object.hash(weekStart, dayIndex, slotIndex);

  @override
  String toString() =>
      'PlannerSlotRef(week: $weekStart, day: $dayIndex, slot: $slotIndex)';
}
