import 'package:flutter/material.dart';

import 'package:optimeal/models/recipe_scale.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/diagram_sheet.dart';

/// One ingredient line: quantity + name, with an optional cut pill.
///
/// **Built once, rendered twice.** This is the row the recipe overview shows
/// today and the row the pre-cook merge's Step 1 will show next — the same
/// widget, so a formatting fix lands on both and they cannot drift the way the
/// spoon-bowl illustration did.
///
/// Read-only by design: nothing here is tickable. The checklist behaviour
/// belongs to the pre-cook surface, not to a row component, and baking it in
/// would force the overview to own state it has no use for.
class IngredientRow extends StatelessWidget {
  const IngredientRow({
    super.key,
    required this.ingredient,
    this.cutDiagramKey,
    this.dense = false,
  });

  final ScaledIngredient ingredient;

  /// A cut key that has a **built** diagram, or null. Callers resolve this
  /// through `cut_key_resolver.dart`, which already refuses unbuilt keys and
  /// technique keys — this widget renders whatever it is handed.
  final String? cutDiagramKey;

  /// Tighter vertical rhythm, for the compact have-out grouping.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final key = cutDiagramKey;
    final diagram = key == null ? null : diagramFor(key);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 3 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ingredient.displayAmount.isNotEmpty) ...[
            // Fixed-width quantity column so the names line up down the list
            // rather than stepping in and out with each number's width.
            SizedBox(
              width: 68,
              child: Text(
                ingredient.displayAmount,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppDesignTokens.textCharcoal,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  ingredient.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppDesignTokens.textCharcoal.withValues(alpha: 0.88),
                    height: 1.35,
                  ),
                ),
                if (ingredient.roundedUp)
                  Text(
                    // SIGNED-CONTENT PLACEHOLDER
                    '· rounded up',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          AppDesignTokens.textCharcoal.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (diagram != null)
                  DiagramPill(diagramKey: key!, title: diagram.title),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
