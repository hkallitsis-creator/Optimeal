import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/weekly_planner_intent_service.dart';
import 'package:optimeal/theme.dart';
import 'package:optimeal/widgets/app_bottom_sheet.dart';
import 'package:optimeal/widgets/weekday_picker_sheet.dart';

/// Shows a compact recipe preview with two actions:
/// - "Cook Now" -> opens Cook Mode
/// - "Plan for Day" -> queues an add-to-weekly-plan intent
class GeneratedRecipeActionsSheet extends StatelessWidget {
  const GeneratedRecipeActionsSheet({super.key, required this.recipe, required this.sourceLabel});

  final CookModeRecipePayload recipe;
  final String sourceLabel;

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
                      context.push(AppRoutes.onePanCookingRoadmap, extra: recipe);
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