import 'package:flutter/foundation.dart';

import 'package:optimeal/models/planner_slot_ref.dart';
import 'package:optimeal/services/data_change_signal.dart';
import 'package:optimeal/services/weekly_plan_service.dart';

/// Writes back the one thing a finished cook knows about the Weekly Planner:
/// that the slot it was launched from has now been cooked.
///
/// This closes CLAUDE.md roadmap item 27. The planner renders both cooked
/// states — gold check when the cook counted toward the Waste Ledger, neutral
/// when it did not — from `user_meal_plans.is_cooked`, but until now nothing
/// set that column, so neither state was reachable in the running app. The
/// deleted writer (the planner awaiting `push<bool>` from Cook Mode) could not
/// work, because the post-cook `context.go('/')` removes the planner page and
/// completes that future with null.
///
/// **The attribution is carried, never inferred.** [PlannerSlotRef] is stamped
/// once, at launch, on the planner row the user actually pressed Cook on, and
/// rides in `CookModeLaunchRequest` (and through the saved active session, so
/// an interrupted planner cook still attributes when it is resumed). A cook
/// launched from Home, the Fridge Clearer, a generation sheet or Recently
/// Cooked carries null and touches no plan row at all. There is no title
/// matching anywhere in this path: the same dish planned on Tuesday and Friday
/// flips only the row that was launched.
///
/// **Counted-ness is not decided here and is not stored.** Whether a cooked
/// meal shows the gold check or the neutral one stays derived at read time
/// from the recipe's own `RecipeOrigin.isRescueEligible` — the same rule
/// `selectLedgerVerdict` applies — so this service writes one boolean and
/// nothing else. That is also why it needs no ledger result and does not care
/// whether the ledger write succeeded.
class PlannerCookAttributionService {
  PlannerCookAttributionService({WeeklyPlanBackend? backend})
      : _backend = backend ?? SupabaseWeeklyPlanBackend();

  final WeeklyPlanBackend _backend;

  /// Marks [slot] cooked, if there is one.
  ///
  /// Returns true only when a write was actually issued, which is what the
  /// tests assert on — "no planner row was touched" is a real, required
  /// outcome for every non-planner cook, not an absence of behaviour.
  ///
  /// Never throws and never blocks the post-cook sequence: a failed write
  /// leaves the row uncooked, which is a stale planner row rather than a
  /// broken cook. The planner's own optimistic-write path already owns the
  /// visible retry affordance for writes the *user* initiated; this one is a
  /// side effect of finishing a cook and stays silent.
  Future<bool> markCookedFromCompletion({
    required PlannerSlotRef? slot,
    required bool isReCook,
  }) async {
    if (slot == null) return false;
    // A re-cook (Home's Recently Cooked) is excluded for the same reason it is
    // excluded from the ledger: the event already happened once. In practice
    // it cannot carry a slot anyway — belt and braces.
    if (isReCook) return false;

    final userId = _backend.currentUserId;
    if (userId == null) {
      debugPrint(
          'PlannerCookAttribution: no signed-in user, leaving $slot unmarked.');
      return false;
    }

    try {
      await _backend.markSlotCooked(
        userId: userId,
        dayIndex: slot.dayIndex,
        slotIndex: slot.slotIndex,
        cooked: true,
      );
    } catch (e) {
      debugPrint('PlannerCookAttribution: failed to mark $slot cooked: $e');
      return false;
    }

    // Announced only after the write has landed — see AppDataChanges.mealPlan
    // for why this cannot ride on the cookLog signal the same completion also
    // raises.
    AppDataChanges.mealPlan.notify();
    return true;
  }
}
