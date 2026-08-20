import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/saved_recipes_service.dart';
import 'package:optimeal/theme.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/save_recipe_bookmark_button.dart';

/// Renders the "not counted" / "write failed and queued" Waste Ledger
/// verdicts (docs/DECISIONS.md "Waste Ledger legibility — option B"). The
/// "counted" verdict has no equivalent widget — [WasteLedgerCelebrationSheet]
/// already serves that role; this sheet is only ever shown for the other
/// cases (never both in the same sequence).
///
/// Extracted from `one_pan_cooking_roadmap_screen.dart` (where it was the
/// private `_LedgerVerdictSheet`) so the CTA-last rule below can be asserted
/// by a widget test.
///
/// **The signed post-cook sequence is load-bearing.** Verdict copy is
/// unchanged, and the exit-to-Home CTA MUST remain the last element in this
/// column — it is the only working way out of a finished cook (device-test
/// round F3). The optional bookmark is quiet, sits in the header row beside
/// the icon, and is never a step: no copy, no prompt, nothing to dismiss.
class LedgerVerdictSheet extends StatelessWidget {
  const LedgerVerdictSheet({
    super.key,
    required this.line,
    this.recipe,
    this.service,
  });

  final String line;

  /// When present, a quiet bookmark appears in the header row. Absent for the
  /// demo recipe, which has nothing meaningful to save.
  final CookModeRecipePayload? recipe;

  /// Injectable for tests. Defaults to the shared singleton.
  final SavedRecipesService? service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final payload = recipe;

    return Material(
      color: AppDesignTokens.surfaceCream,
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
                    color: AppDesignTokens.deepForest.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color:
                            AppDesignTokens.deepForest.withValues(alpha: 0.18)),
                  ),
                  child: const Icon(Icons.eco_outlined,
                      color: AppDesignTokens.deepForest, size: 22),
                ),
                const Spacer(),
                if (payload != null)
                  SaveRecipeBookmarkButton(recipe: payload, service: service),
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
