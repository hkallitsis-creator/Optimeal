import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:optimeal/models/user_profile.dart';
import 'package:optimeal/services/confidence_climb_service.dart';
import 'package:optimeal/theme.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/app_bottom_sheet.dart';

/// One-time "move up a kitchen-confidence tier?" prompt, offered by
/// [ConfidenceClimbService] once the user has racked up enough
/// technique-tagged cook reps. Returns true if the user accepted, false
/// (or null, if dismissed via backdrop/drag) otherwise — the caller is
/// responsible for actually updating [UserProfile.kitchenConfidence] and
/// for calling [ConfidenceClimbService.markPrompted] either way, so this
/// tier is never offered again regardless of the answer.
///
/// See CLAUDE.md Retention Features Backlog item 2 (Confidence Climb).
class ConfidenceTierUpSheet extends StatelessWidget {
  const ConfidenceTierUpSheet({super.key, required this.targetTier});

  final KitchenConfidence targetTier;

  static Future<bool?> show(BuildContext context, {required KitchenConfidence targetTier}) {
    return AppBottomSheet.show<bool>(
      context: context,
      builder: (ctx) => SafeArea(child: ConfidenceTierUpSheet(targetTier: targetTier)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tierName = ConfidenceClimbService.tierDisplayName(targetTier);

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
                    color: AppDesignTokens.deepForest.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppDesignTokens.deepForest.withValues(alpha: 0.18)),
                  ),
                  child: const Icon(Icons.trending_up_rounded, color: AppDesignTokens.deepForest, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Move up to $tierName?',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: AppDesignTokens.textCharcoal),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "You've been cooking with real technique lately. Moving up means Chef Harris will stop holding back — "
              'more ambitious recipes, more multitasking, less hand-holding on the basics.',
              style: theme.textTheme.bodyMedium?.copyWith(color: AppDesignTokens.textCharcoal, height: 1.35, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: AppSizing.primaryButtonHeight,
              child: FilledButton(
                onPressed: () => context.pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignTokens.ctaTerracotta,
                  foregroundColor: scheme.onTertiary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: Text(
                  'Move up to $tierName',
                  style: theme.textTheme.labelLarge?.copyWith(color: scheme.onTertiary, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => context.pop(false),
                child: Text(
                  'Not yet',
                  style: theme.textTheme.labelLarge?.copyWith(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.75), fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
