import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:optimeal/models/recipe_scale.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/cut_key_resolver.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/ingredient_row.dart';
import 'package:optimeal/widgets/recipe_provenance_badges.dart';

/// The recipe overview — the screen between choosing a recipe and Cook Mode.
///
/// # What this replaced, and why
///
/// A half-screen terracotta hero block above the fold, a three-line
/// description, a bulleted list reading "4 piece Eggs" and "0.3 tsp Black
/// Pepper", a "Mode: Cook Mode" pill that restated the screen you were on, and
/// an inline copy of every step. Worst of all, from My Recipes there was **no
/// way to cook the recipe at all** — a saved recipe could be read and never
/// made.
///
/// Now: a modest empty photo slot, title, one-line description, provenance,
/// a meta card carrying the servings stepper, gear, ingredients, and a pinned
/// Start cooking CTA that works from every entry point.
///
/// # The servings stepper lives here and only here
///
/// It rescales quantities live from structured data and **freezes when Cook
/// Mode opens** — the chosen N rides on `CookModeLaunchRequest.servings`, is
/// read once on mount, and is never written onto the recipe payload. Popping
/// back here makes the stepper live again.
///
/// The old inline stepper on Cook Mode's ingredients checklist is still
/// present and still works; it is the pre-cook merge's job to remove it. Until
/// then this app has two steppers, and **this one is authoritative** — it is
/// the one whose value reaches Cook Mode.
class RecipeOverviewBody extends StatelessWidget {
  const RecipeOverviewBody({
    super.key,
    required this.recipe,
    required this.servings,
    required this.onServingsChanged,
    this.enabled = true,
  });

  final CookModeRecipePayload recipe;

  /// The live servings count. Owned by the screen rather than by this widget,
  /// because the pinned CTA also needs it and lives outside this subtree.
  final int servings;

  final ValueChanged<int> onServingsChanged;

  /// False while a cook session is in progress for this recipe (audit M-1):
  /// quantities are locked from Start cooking, so the stepper shows the
  /// locked N read-only instead of a live control the resume would ignore.
  final bool enabled;

  /// A recipe that never declared what it was written for cannot be scaled
  /// from anything, so the stepper is disabled rather than multiplying by a
  /// number nobody asserted.
  bool get _scalable => (recipe.basePortions ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // See RecipeDetailsScreen: an un-onboarded profile has not "set" a
    // household, whatever its default field value says.
    final household = context.select<UserProfileController, int?>(
      (c) => c.profile.onboarded ? c.profile.householdServings : null,
    );
    final ceiling = servingsCeilingFor(householdServings: household);

    final structured = recipe.structuredIngredients;
    final scaled = structured == null || structured.isEmpty
        ? const <ScaledIngredient>[]
        : scaleIngredients(
            ingredients: structured,
            basePortions: recipe.basePortions,
            servings: servings,
          );

    final description = recipe.description?.trim() ?? '';
    final gear = recipe.kitchenGear ?? const <String>[];
    final minutes =
        estimatedMinutes(recipe.steps.map((s) => s.durationMinutes));
    final isFridgeRescue = recipe.origin?.isRescueEligible ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Photo slot — DEFERRED, reserved ────────────────────────────────
        // No camera in v1. A modest fixed-height ivory band, empty and
        // untextured, so the layout already has the room when a photo lands.
        // Explicitly NOT the half-screen terracotta hero this replaced.
        Container(
          height: 96,
          width: double.infinity,
          color: AppDesignTokens.surfaceIvory,
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                recipe.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                  color: AppDesignTokens.deepForest,
                ),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  description,
                  // One quiet sentence, never a paragraph. The old screen let
                  // this run to three lines and push everything below the fold.
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color:
                        AppDesignTokens.textCharcoal.withValues(alpha: 0.70),
                  ),
                ),
              ],
              if (isFridgeRescue) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const ProvenanceLeafBadge(),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        // SIGNED-CONTENT PLACEHOLDER
                        'fridge rescue',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppDesignTokens.textCharcoal
                              .withValues(alpha: 0.70),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 20),
              _MetaCard(
                minutes: minutes,
                stepCount: recipe.steps.length,
                servings: servings,
                enabled: _scalable && enabled,
                min: kServingsMin,
                max: ceiling,
                onChanged: onServingsChanged,
              ),

              if (gear.isNotEmpty) ...[
                const SizedBox(height: 14),
                _GearCard(gear: gear),
              ],

              const SizedBox(height: 14),
              _IngredientsCard(
                scaled: scaled,
                // Older recipes and the demo body have no structured data;
                // fall back to the display strings rather than an empty card.
                fallback: scaled.isEmpty ? recipe.ingredients : const [],
                steps: recipe.steps,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Left: the quiet meta line the "Est. time" pill-card became. Right: the
/// servings stepper, which is this surface's whole reason for existing.
class _MetaCard extends StatelessWidget {
  const _MetaCard({
    required this.minutes,
    required this.stepCount,
    required this.servings,
    required this.enabled,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int minutes;
  final int stepCount;
  final int servings;
  final bool enabled;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _OverviewCard(
      child: Row(
        children: [
          Expanded(
            child: Text(
              '~$minutes min · $stepCount step${stepCount == 1 ? '' : 's'}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppDesignTokens.textCharcoal.withValues(alpha: 0.75),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _StepperGlyph(
            icon: Icons.remove_rounded,
            onTap: enabled && servings > min ? () => onChanged(servings - 1) : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              // SIGNED-CONTENT PLACEHOLDER
              'Serves $servings',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppDesignTokens.textCharcoal,
              ),
            ),
          ),
          _StepperGlyph(
            icon: Icons.add_rounded,
            onTap: enabled && servings < max ? () => onChanged(servings + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _StepperGlyph extends StatelessWidget {
  const _StepperGlyph({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 22,
          color: disabled
              ? AppDesignTokens.textCharcoal.withValues(alpha: 0.28)
              : AppDesignTokens.ctaTerracotta,
        ),
      ),
    );
  }
}

class _GearCard extends StatelessWidget {
  const _GearCard({required this.gear});

  final List<String> gear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _OverviewCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: Icon(Icons.kitchen_outlined,
                size: 20,
                color: AppDesignTokens.textCharcoal.withValues(alpha: 0.65)),
          ),
          Expanded(
            // Wrap, never clip — kit rule.
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in gear)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      // Champagne: requirements wear it even though they are
                      // not tappable. Signed.
                      color: AppDesignTokens.champagneTint,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      item,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppDesignTokens.terracottaOnLight,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IngredientsCard extends StatelessWidget {
  const _IngredientsCard({
    required this.scaled,
    required this.fallback,
    required this.steps,
  });

  final List<ScaledIngredient> scaled;
  final List<String> fallback;
  final List<CookModeStepPayload> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _OverviewCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // SIGNED-CONTENT PLACEHOLDER
            'What you need',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppDesignTokens.deepForest.withValues(alpha: 0.75),
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in scaled)
            IngredientRow(
              ingredient: item,
              cutDiagramKey:
                  resolveCutDiagramKey(ingredient: item.raw, steps: steps),
            ),
          for (final line in fallback)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                line,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppDesignTokens.textCharcoal.withValues(alpha: 0.88),
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceIvory,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        border: Border.all(
            color: AppDesignTokens.textCharcoal.withValues(alpha: 0.10)),
      ),
      child: child,
    );
  }
}

/// The pinned bottom bar: quiet Plan square + the one terracotta CTA.
class RecipeOverviewBottomBar extends StatelessWidget {
  const RecipeOverviewBottomBar({
    super.key,
    required this.onPlan,
    required this.onStartCooking,
  });

  final VoidCallback onPlan;
  final VoidCallback onStartCooking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
        child: Row(
          children: [
            SizedBox(
              height: AppSizing.primaryButtonHeight,
              width: AppSizing.primaryButtonHeight,
              child: OutlinedButton(
                onPressed: onPlan,
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  side: BorderSide(
                      color: AppDesignTokens.textCharcoal
                          .withValues(alpha: 0.22)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: const Icon(Icons.calendar_month_outlined,
                    size: 22, color: AppDesignTokens.textCharcoal),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: AppSizing.primaryButtonHeight,
                child: FilledButton(
                  onPressed: onStartCooking,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppDesignTokens.ctaTerracotta,
                    foregroundColor: scheme.onTertiary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  child: Text(
                    // SIGNED-CONTENT PLACEHOLDER
                    'Start cooking',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onTertiary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
