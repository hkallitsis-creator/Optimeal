import 'package:flutter/material.dart';

import 'package:optimeal/theme/app_design_tokens.dart';

/// The leaf badge: shown **only** on recipes whose origin is Fridge Clearer.
///
/// Provenance is carried by the recipe itself ([RecipeOrigin]), so this badge
/// means the same thing on a saved card, a planner row, and a picker row —
/// and keeps meaning it after the recipe has travelled through
/// `recipe_payload` jsonb. Never render it from a launch surface or a guess.
class ProvenanceLeafBadge extends StatelessWidget {
  const ProvenanceLeafBadge({super.key, this.compact = false});

  /// Icon-only, for dense list rows.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (compact) {
      return const Icon(Icons.eco_rounded,
          size: 16, color: AppDesignTokens.deepForest);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppDesignTokens.deepForest.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: AppDesignTokens.deepForest.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.eco_rounded,
              size: 12, color: AppDesignTokens.deepForest),
          const SizedBox(width: 4),
          Text(
            'Fridge rescue', // SIGNED-CONTENT PLACEHOLDER
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppDesignTokens.deepForest,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// Marks a planned meal that came off the user's My recipes shelf, as opposed
/// to being generated for that slot. Separate from [ProvenanceLeafBadge] on
/// purpose — one describes where the recipe was *generated*, the other how it
/// got into *this* day. A saved Fridge Clearer recipe carries both.
class FromSavedChip extends StatelessWidget {
  const FromSavedChip({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppDesignTokens.textCharcoal.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: AppDesignTokens.textCharcoal.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_rounded,
              size: 12,
              color: AppDesignTokens.textCharcoal.withValues(alpha: 0.70)),
          const SizedBox(width: 4),
          Text(
            'From saved', // SIGNED-CONTENT PLACEHOLDER
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppDesignTokens.textCharcoal.withValues(alpha: 0.80),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
