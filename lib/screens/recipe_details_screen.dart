import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:optimeal/models/recipe_scale.dart';
import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/saved_recipes_service.dart';
import 'package:optimeal/services/weekly_planner_intent_service.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/app_bottom_sheet.dart';
import 'package:optimeal/widgets/home_glyph_button.dart';
import 'package:optimeal/widgets/recipe_overview_body.dart';
import 'package:optimeal/widgets/save_recipe_bookmark_button.dart';
import 'package:optimeal/widgets/weekday_picker_sheet.dart';

/// The recipe overview screen — every path between choosing a recipe and
/// Cook Mode lands here.
///
/// # The device bug this closes
///
/// Recipes opened from My Recipes (Saved and Recently Cooked) reached this
/// screen with **no cook affordance at all**. A saved recipe could be read and
/// never made again, which quietly made the whole Saved feature a read-only
/// archive. The pinned "Start cooking" CTA is the fix.
///
/// # Re-cooking preserves provenance, and never mutates the old cook
///
/// The launch carries `surface: null` and does **not** set `isReCook`.
/// Rescue eligibility is a property of the RECIPE (`RecipeOrigin`), not of the
/// screen that launched it, so a saved Fridge Clearer recipe cooked again
/// still counts as a rescue. Leaving `isReCook` false is deliberate: a re-cook
/// flagged true never logs, and this cook is a real cook that earns its own
/// new cook-log row.
class RecipeDetailsScreen extends StatefulWidget {
  const RecipeDetailsScreen({super.key, this.recipe, this.service});

  /// The recipe to show. Passed as go_router's `extra` — see
  /// `AppRoutes.recipe`. Null keeps the pre-existing static demo body, which
  /// is what the bare `/recipe` route has always rendered; nothing else in
  /// the app reaches that path.
  final CookModeRecipePayload? recipe;

  /// Injectable for tests. Defaults to the shared singleton.
  final SavedRecipesService? service;

  @override
  State<RecipeDetailsScreen> createState() => _RecipeDetailsScreenState();
}

class _RecipeDetailsScreenState extends State<RecipeDetailsScreen> {
  /// Live servings. Null until the user touches the stepper, so the signed
  /// default precedence keeps applying as profile data loads.
  ///
  /// **Not persisted, and deliberately not written onto the payload** — the
  /// payload is what goes into `saved_recipes` and `user_meal_plans`, and a
  /// saved recipe must not remember one evening's headcount. This value lives
  /// exactly as long as the route does, which is also what makes the
  /// lock/unlock behaviour fall out for free: Cook Mode reads the number once
  /// at launch, and popping back here re-enables the stepper because this
  /// State was never disposed.
  int? _servings;

  int _resolveServings(CookModeRecipePayload recipe, int? household) =>
      _servings ??
      defaultServingsFor(
        // PlannerSlotRef carries week/day/slot and no headcount, so the first
        // tier of the signed precedence has no data source yet. See the
        // session record.
        plannerServings: null,
        profileHouseholdServings: household,
        recipeBasePortions: recipe.basePortions,
      );

  void _startCooking(CookModeRecipePayload recipe, int servings) {
    context.push(
      AppRoutes.onePanCookingRoadmap,
      extra: CookModeLaunchRequest(
        recipe: recipe,
        surface: null,
        servings: servings,
      ),
    );
  }

  Future<void> _plan(CookModeRecipePayload recipe) async {
    final dayIndex = await AppBottomSheet.show<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppDesignTokens.surfaceIvory,
      builder: (ctx) => const SafeArea(
        // SIGNED-CONTENT PLACEHOLDER
        child: WeekdayPickerSheet(title: 'Plan for which day?'),
      ),
    );
    if (dayIndex == null || !mounted) return;

    WeeklyPlannerIntentService.instance.queueAddMeal(
      dayIndex: dayIndex,
      recipe: recipe,
      source: kFromSavedMealSource,
    );
    if (!mounted) return;
    context.push(AppRoutes.weeklyPlan);
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.recipe;
    // "if set" is load-bearing: UserProfile.empty() reports a household of 1
    // on a non-nullable field, so an un-onboarded profile would silently
    // out-rank the recipe's own basePortions and open every recipe at Serves 1.
    // `onboarded` is the honest proxy for "the user actually told us".
    final household = context.select<UserProfileController, int?>(
      (c) => c.profile.onboarded ? c.profile.householdServings : null,
    );

    return Scaffold(
      backgroundColor: AppDesignTokens.backgroundSage,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // Depth-2 (reached only through another screen): back plus the quiet
        // home glyph, now that the bottom nav bar is gone.
        leadingWidth: kBackWithHomeLeadingWidth,
        leading: BackWithHomeLeading(
          back: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        // The universal bookmark, quiet, top-right. Pre-cook saving's home.
        actions: [
          if (payload != null)
            SaveRecipeBookmarkButton(
                recipe: payload, service: widget.service),
        ],
      ),
      body: payload == null
          ? const _MissingRecipeBody()
          : SingleChildScrollView(
              child: RecipeOverviewBody(
                recipe: payload,
                servings: _resolveServings(payload, household),
                onServingsChanged: (v) => setState(() => _servings = v),
              ),
            ),
      bottomNavigationBar: payload == null
          ? null
          : RecipeOverviewBottomBar(
              onPlan: () => _plan(payload),
              onStartCooking: () => _startCooking(
                payload,
                _resolveServings(payload, household),
              ),
            ),
    );
  }
}

/// What the bare `/recipe` route renders. Nothing in the app navigates here
/// without a recipe; this exists so a deep link cannot produce a blank screen.
class _MissingRecipeBody extends StatelessWidget {
  const _MissingRecipeBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          // SIGNED-CONTENT PLACEHOLDER
          'No recipe to show.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: AppDesignTokens.textCharcoal.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }
}
