import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/saved_recipes_service.dart';
import 'package:optimeal/services/weekly_planner_intent_service.dart';
import 'package:optimeal/theme.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/app_bottom_sheet.dart';
import 'package:optimeal/widgets/save_recipe_bookmark_button.dart';
import 'package:optimeal/widgets/weekday_picker_sheet.dart';

/// Shows a compact recipe preview with two actions:
/// - "Cook Now" -> opens Cook Mode
/// - "Plan for Day" -> queues an add-to-weekly-plan intent
///
/// Plus the universal bookmark in the header row (2026-08-21). Same widget,
/// same semantics, same quiet treatment as its other mounts: no label, no
/// copy, never a step. A generated recipe needs nothing persisted first —
/// [SaveRecipeBookmarkButton] keys on the title via
/// [SavedRecipesService.recipeKeyFor] and `save` writes the whole payload
/// inline, exactly as it already does from the post-cook verdict sheets, so
/// there is no not-yet-saved special case to handle here.
class GeneratedRecipeActionsSheet extends StatelessWidget {
  const GeneratedRecipeActionsSheet({
    super.key,
    required this.recipe,
    required this.sourceLabel,
    required this.surface,
    this.service,
  });

  final CookModeRecipePayload recipe;
  final String sourceLabel;

  /// Injectable for tests. Defaults to the shared singleton.
  final SavedRecipesService? service;

  /// Which surface generated [recipe] — this widget is shared by Fridge
  /// Countdown and Custom AI Recipe Creator, which need to be
  /// distinguishable for Waste Ledger gating (see RecipeOrigin).
  final CookModeSurface surface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ingredientsPreview = recipe.ingredients.take(6).toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: scheme.tertiary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.tertiary.withValues(alpha: 0.18)),
                ),
                child: Icon(Icons.restaurant_rounded, color: scheme.tertiary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Generated recipe', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              ),
              SaveRecipeBookmarkButton(recipe: recipe, service: service),
              IconButton(
                onPressed: () => context.pop(),
                icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                style: const ButtonStyle(overlayColor: WidgetStatePropertyAll(Colors.transparent)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(recipe.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, height: 1.1)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final ing in ingredientsPreview)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: scheme.outline.withValues(alpha: 0.16)),
                  ),
                  child: Text(ing, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
              if (recipe.ingredients.length > ingredientsPreview.length)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: scheme.outline.withValues(alpha: 0.16)),
                  ),
                  child: Text('+${recipe.ingredients.length - ingredientsPreview.length} more', style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: AppSizing.primaryButtonHeight,
                  child: FilledButton.icon(
                    onPressed: () {
                      context.pop();
                      context.push(
                        AppRoutes.onePanCookingRoadmap,
                        extra: CookModeLaunchRequest(recipe: recipe, surface: surface),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.tertiary,
                      foregroundColor: scheme.onTertiary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    icon: Icon(Icons.local_fire_department_rounded, color: scheme.onTertiary),
                    label: Text('🔥 Cook Now', style: theme.textTheme.labelLarge?.copyWith(color: scheme.onTertiary, fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: AppSizing.primaryButtonHeight,
                  child: OutlinedButton(
                    onPressed: () async {
                      final dayIndex = await AppBottomSheet.show<int>(
                        context: context,
                        isScrollControlled: false,
                        showDragHandle: true,
                        backgroundColor: AppDesignTokens.surfaceIvory,
                        builder: (ctx) => const SafeArea(child: WeekdayPickerSheet(title: '📅 Plan for which day?')),
                      );
                      if (dayIndex == null || !context.mounted) return;
                      WeeklyPlannerIntentService.instance.queueAddMeal(dayIndex: dayIndex, recipe: recipe, source: sourceLabel);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Added to ${WeekdayPickerSheet.labelsLong[dayIndex]}!'), behavior: SnackBarBehavior.floating),
                      );
                      context.pop();
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: scheme.surface,
                      foregroundColor: scheme.tertiary,
                      side: BorderSide(color: scheme.tertiary.withValues(alpha: 0.85), width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ).copyWith(
                      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                    ),
                    child: Text('📅 Plan for Day', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900, color: scheme.tertiary)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}