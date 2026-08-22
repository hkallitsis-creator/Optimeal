import 'package:flutter/material.dart';

import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/models/recipe_scale.dart';
import 'package:optimeal/services/cut_key_resolver.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/ingredient_row.dart';

/// Step 1 — mise en place. The checklist and the first step, merged.
///
/// # It is a read, not a task list
///
/// What this replaced was an "Ingredients Checklist" card with tick rows, an
/// `0/N` counter and its own servings stepper, sitting *above* a step list
/// that then opened with a near-identical prep step. Two surfaces saying the
/// same thing, one of them asking to be ticked off.
///
/// **Nothing here is tickable, and no "confirm you've prepped" interaction may
/// be reintroduced in any form.** No ticks, no strikethrough, no counter. The
/// quantities just stay legible.
///
/// # Synthesized, and exempt
///
/// Built client-side from structured ingredient data — no prompt change, zero
/// token cost. It carries no sensory cue, no timer and no heat pill, is not
/// seen by the compatibility or safety validators, and never reaches a prompt
/// payload. It is not a cooking step and is not treated as one.
///
/// The servings pill is **read-only**. The adjuster's only home is the recipe
/// overview; this shows what was locked in when Cook Mode opened.
///
/// **This card carries no CTA.** The spec's Step 1 CTA ("Board's clear — heat
/// goes on") IS the step system's own Next button in the bottom bar, relabelled
/// — putting a second filled button inside the card would break the
/// one-terracotta-CTA kit rule.
class MiseEnPlaceCard extends StatelessWidget {
  const MiseEnPlaceCard({
    super.key,
    required this.stepNumber,
    required this.title,
    required this.servings,
    required this.structuredIngredients,
    required this.basePortions,
    required this.fallbackIngredients,
    required this.steps,
    this.nextStepTitle,
    this.onWhisperTap,
  });

  final int stepNumber;
  final String title;

  /// The locked servings count. Read-only here by design.
  final int servings;

  final List<RecipeIngredient>? structuredIngredients;
  final int? basePortions;

  /// Plain display strings, used when a recipe has no structured data.
  final List<String> fallbackIngredients;

  /// The recipe's steps, so the cut resolver can read prose where the model
  /// declared no cut.
  final List<CookModeStepPayload> steps;

  final String? nextStepTitle;
  final VoidCallback? onWhisperTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final structured = structuredIngredients ?? const <RecipeIngredient>[];
    final scaled = structured.isEmpty
        ? const <ScaledIngredient>[]
        : scaleIngredients(
            ingredients: structured,
            basePortions: basePortions,
            servings: servings,
          );

    // Grouping uses the resolved cut key (any signed vocabulary value); the
    // PILL uses the diagram form (built diagrams only). An ingredient with a
    // recognized-but-undrawn cut still belongs under the knife — it just gets
    // no pill.
    final knife = <({ScaledIngredient row, String? pill})>[];
    final haveOut = <ScaledIngredient>[];

    for (final row in scaled) {
      final cut = resolveCutKey(ingredient: row.raw, steps: steps);
      if (cut != null) {
        knife.add((
          row: row,
          pill: resolveCutDiagramKey(ingredient: row.raw, steps: steps),
        ));
      } else {
        haveOut.add(row);
      }
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceIvory,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        border: Border.all(
            color: AppDesignTokens.textCharcoal.withValues(alpha: 0.10)),
        boxShadow: AppDesignTokens.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1 — number chip + title
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppDesignTokens.champagneTint,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$stepNumber',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppDesignTokens.terracottaOnLight,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                          color: AppDesignTokens.deepForest,
                        ),
                      ),
                    ),
                  ],
                ),

                // 2 — meta pills. No heat pill, no timer, and the serves pill
                // has no control on it.
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    const _MetaPill(
                      icon: Icons.local_fire_department_outlined,
                      // SIGNED-CONTENT PLACEHOLDER
                      label: 'No heat yet',
                    ),
                    _MetaPill(
                      icon: Icons.people_outline_rounded,
                      // SIGNED-CONTENT PLACEHOLDER
                      label: 'Serves $servings · set on recipe page',
                    ),
                  ],
                ),

                // 3 — one sage teaching line. No cue-panel machinery: prep has
                // no sensory cue and the cue data contract is not touched.
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: AppDesignTokens.sageTeachingPanel,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    // SIGNED-CONTENT PLACEHOLDER
                    'Everything cut and within reach before the pan gets hot.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppDesignTokens.textCharcoal,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                if (knife.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const _SectionLabel('NEEDS THE KNIFE'),
                  const SizedBox(height: 4),
                  for (final entry in knife)
                    IngredientRow(
                      ingredient: entry.row,
                      cutDiagramKey: entry.pill,
                    ),
                ],

                if (haveOut.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const _SectionLabel('JUST HAVE IT OUT'),
                  const SizedBox(height: 6),
                  Text(
                    haveOut.map((r) => r.displayLine).join(' · '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          AppDesignTokens.textCharcoal.withValues(alpha: 0.88),
                      height: 1.4,
                    ),
                  ),
                ],

                // Unstructured recipes (demo, pre-structured-data saves) keep
                // a plain readable list rather than an empty card.
                if (scaled.isEmpty && fallbackIngredients.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const _SectionLabel('JUST HAVE IT OUT'),
                  const SizedBox(height: 6),
                  Text(
                    fallbackIngredients.join(' · '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          AppDesignTokens.textCharcoal.withValues(alpha: 0.88),
                      height: 1.4,
                    ),
                  ),
                ],

              ],
            ),
          ),

          // 6 — the next-step whisper, fused to the bottom edge, same shape
          // as the focused step card's.
          if (nextStepTitle != null)
            InkWell(
              onTap: onWhisperTap,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                color: AppDesignTokens.quietRowSurface,
                child: Text(
                  // SIGNED-CONTENT PLACEHOLDER
                  'Next · $nextStepTitle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppDesignTokens.textCharcoal.withValues(alpha: 0.60),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      // SIGNED-CONTENT PLACEHOLDER
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: AppDesignTokens.deepForest.withValues(alpha: 0.70),
        fontWeight: FontWeight.w900,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppDesignTokens.neutralPillTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 15,
              color: AppDesignTokens.textCharcoal.withValues(alpha: 0.65)),
          const SizedBox(width: 6),
          // Flexible, not bare: the serves label carries a placeholder suffix
          // and overflowed a 360 px pill without it. Wrap never clip.
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppDesignTokens.textCharcoal.withValues(alpha: 0.80),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
