import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/theme.dart';
import 'package:optimeal/theme/app_design_tokens.dart';

/// A compact celebration bottom sheet shown as the definitive last screen
/// after a completed cook logs a counted Waste Ledger rescue.
///
/// Redesigned (device-test round F3): one icon, one line of copy, one CTA
/// that leaves the finished cook and lands on Home — where the full ledger
/// totals (and the itemized ingredient list, via the This Week card) are
/// actually visible. Replaces the old multi-line layout and the "Well
/// done" button, which only popped the sheet and left Cook Mode's
/// already-finished screen sitting there with nowhere else to go.
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

    final rescuedCount = ingredientsRescued
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .length;

    final line =
        'Nice rescue — $rescuedCount ingredient${rescuedCount == 1 ? '' : 's'} saved, '
        '$lifetimeIngredientsRescued lifetime.';

    return Material(
      color: AppDesignTokens.surfaceCream,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: AppDesignTokens.ctaTerracotta.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color:
                        AppDesignTokens.ctaTerracotta.withValues(alpha: 0.18)),
              ),
              child: const Icon(Icons.eco_rounded,
                  color: AppDesignTokens.ctaTerracotta, size: 22),
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
