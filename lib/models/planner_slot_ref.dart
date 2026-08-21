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
  const PlannerSlotRef({required this.dayIndex, required this.slotIndex});

  /// Monday-based day of the week, matching `user_meal_plans.day_index`.
  final int dayIndex;

  /// 0-based position within the day, matching `user_meal_plans.slot_index`.
  final int slotIndex;

  Map<String, dynamic> toJson() => {
        'dayIndex': dayIndex,
        'slotIndex': slotIndex,
      };

  /// Tolerant by design: this is read back out of a locally persisted active
  /// cook session, which may have been written by an older build that had no
  /// such field at all. Anything unusable reads as "no slot", which is the
  /// safe answer — it attributes nothing rather than attributing wrongly.
  static PlannerSlotRef? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final day = int.tryParse('${raw['dayIndex'] ?? raw['day_index'] ?? ''}'.trim());
    final slot = int.tryParse('${raw['slotIndex'] ?? raw['slot_index'] ?? ''}'.trim());
    if (day == null || slot == null) return null;
    if (day < 0 || slot < 0) return null;
    return PlannerSlotRef(dayIndex: day, slotIndex: slot);
  }

  @override
  bool operator ==(Object other) =>
      other is PlannerSlotRef &&
      other.dayIndex == dayIndex &&
      other.slotIndex == slotIndex;

  @override
  int get hashCode => Object.hash(dayIndex, slotIndex);

  @override
  String toString() => 'PlannerSlotRef(day: $dayIndex, slot: $slotIndex)';
}
