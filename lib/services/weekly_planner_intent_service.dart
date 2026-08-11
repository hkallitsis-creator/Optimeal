import 'package:flutter/foundation.dart';

import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';

/// Lightweight cross-screen bridge for adding a generated recipe into the
/// Weekly Planner.
///
/// Weekly Planner currently stores its plan in-memory inside the screen.
/// To support "Plan for Day" from other screens without reworking
/// navigation/layout, we pass a one-shot intent that the Weekly Planner
/// consumes when it becomes visible.
class WeeklyPlannerIntentService {
  WeeklyPlannerIntentService._();

  static final WeeklyPlannerIntentService instance = WeeklyPlannerIntentService._();

  /// Mon=0 ... Sun=6
  final ValueNotifier<WeeklyPlannerAddMealIntent?> pendingAddMeal = ValueNotifier(null);

  void queueAddMeal({required int dayIndex, required CookModeRecipePayload recipe, required String source}) {
    pendingAddMeal.value = WeeklyPlannerAddMealIntent(dayIndex: dayIndex, recipe: recipe, source: source);
  }

  WeeklyPlannerAddMealIntent? consumePending() {
    final v = pendingAddMeal.value;
    pendingAddMeal.value = null;
    return v;
  }
}

class WeeklyPlannerAddMealIntent {
  const WeeklyPlannerAddMealIntent({required this.dayIndex, required this.recipe, required this.source});

  final int dayIndex;
  final CookModeRecipePayload recipe;
  final String source;
}
