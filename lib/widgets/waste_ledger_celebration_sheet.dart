import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/saved_recipes_service.dart';
import 'package:optimeal/theme.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/save_recipe_bookmark_button.dart';

/// A compact celebration bottom sheet shown as the definitive last screen
/// after a completed cook logs a counted Waste Ledger rescue.
///
/// Redesigned (device-test round F3): one icon, one line of copy, one CTA
/// that leaves the finished cook and lands on Home — where the full ledger
/// totals (and the itemized ingredient list, via the This Week card) are
/// actually visible. Replaces the old multi-line layout and the "Well
/// done" button, which only popped the sheet and left Cook Mode's
/// already-finished screen sitting there with nowhere else to go.
///
/// **The exit-to-Home CTA MUST remain the last element** in this column. The
/// optional bookmark added alongside it is quiet, sits in the header row, and
/// is never a step in the sequence: no copy, no prompt, nothing to dismiss.
class WasteLedgerCelebrationSheet extends StatelessWidget {
  const WasteLedgerCelebrationSheet({
    super.key,
    required this.ingredientsRescued,
    required this.lifetimeIngredientsRescued,
    this.recipe,
    this.service,
  });

  final List<String> ingredientsRescued;
  final int lifetimeIngredientsRescued;

  /// When present, a quiet bookmark appears in the header row.
  final CookModeRecipePayload? recipe;

  /// Injectable for tests. Defaults to the shared singleton.
  final SavedRecipesService? service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final rescuedCount = ingredientsRescued
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .length;

    final line =
        'Nice rescue — $rescuedCount ingredient${rescuedCount == 1 ? '' : 's'} saved, '
        '$lifetimeIngredientsRescued lifetime.';

    return Material(
      color: AppDesignTokens.surfaceIvory,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    // Gold = earned (palette v1.2). Badge tint fill + a thin
                    // gold border + the contrast-safe gold glyph — never a
                    // large gold fill, never gold on a CTA.
                    color: AppDesignTokens.goldEarnedBadgeTint,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppDesignTokens.goldEarnedFill),
                  ),
                  child: const Icon(Icons.eco_rounded,
                      color: AppDesignTokens.goldEarnedOnLight, size: 22),
                ),
                const Spacer(),
                if (recipe != null)
                  SaveRecipeBookmarkButton(
                      recipe: recipe!, service: service),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              line,
              style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppDesignTokens.textCharcoal,
                  height: 1.35),
            ),
            const SizedBox(height: 18),
            // MUST stay last. See the class doc.
            SizedBox(
              width: double.infinity,
              height: AppSizing.primaryButtonHeight,
              child: FilledButton(
                onPressed: () {
                  context.pop();
                  context.go(AppRoutes.home);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignTokens.ctaTerracotta,
                  foregroundColor: scheme.onTertiary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: Text(
                  'Back to Home',
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onTertiary, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
