import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:optimeal/theme.dart';
import 'package:optimeal/theme/app_design_tokens.dart';

/// A compact celebration bottom sheet shown after logging a “waste ledger” event.
///
/// Intended to be presented via [AppBottomSheet.show] (wired in a later prompt).
class WasteLedgerCelebrationSheet extends StatelessWidget {
  const WasteLedgerCelebrationSheet({
    super.key,
    required this.ingredientsRescued,
    required this.lifetimeIngredientsRescued,
  });

  final List<String> ingredientsRescued;
  final int lifetimeIngredientsRescued;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final rescued = ingredientsRescued
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final rescuedText = rescued.isEmpty ? '—' : rescued.join(', ');
    final rescuedCount = rescued.length;
    final rescuedCountText = rescuedCount == 0
        ? 'Ingredients saved from the bin this time'
        : '$rescuedCount ingredient${rescuedCount == 1 ? '' : 's'} saved from the bin this time';

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
                  height: 38,
                  width: 38,
                  decoration: BoxDecoration(
                    color: AppDesignTokens.ctaTerracotta.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppDesignTokens.ctaTerracotta.withValues(alpha: 0.18)),
                  ),
                  child: const Icon(Icons.eco_rounded, color: AppDesignTokens.ctaTerracotta, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Nice rescue!',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: AppDesignTokens.textCharcoal),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              rescuedText,
              style: theme.textTheme.bodyMedium?.copyWith(color: AppDesignTokens.textCharcoal, height: 1.35, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              rescuedCountText,
              style: theme.textTheme.bodyMedium?.copyWith(color: AppDesignTokens.textCharcoal, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Divider(height: 1, thickness: 1, color: scheme.outline.withValues(alpha: 0.12)),
            const SizedBox(height: 12),
            Text(
              'Lifetime: $lifetimeIngredientsRescued ingredients rescued',
              style: theme.textTheme.labelMedium?.copyWith(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.75), fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: AppSizing.primaryButtonHeight,
              child: FilledButton(
                onPressed: () => context.pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignTokens.ctaTerracotta,
                  foregroundColor: scheme.onTertiary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: Text(
                  'Nice!',
                  style: theme.textTheme.labelLarge?.copyWith(color: scheme.onTertiary, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
