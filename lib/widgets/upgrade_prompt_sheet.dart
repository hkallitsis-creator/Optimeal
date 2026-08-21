import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/theme.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/app_bottom_sheet.dart';

/// Shared upgrade-to-Pro nudge, used at the three moments defined in
/// CLAUDE.md's "Monetization / paywall tier structure": post-cook
/// celebration, the Fridge Clearer weekly cap, and (once built) the Smart
/// Suggestions locked preview. People upgrade when they feel successful or
/// see real value, not when they feel blocked — keep copy warm, not scoldy.
class UpgradePromptSheet extends StatelessWidget {
  const UpgradePromptSheet({super.key, required this.title, required this.message, this.ctaLabel = 'Upgrade to Pro'});

  final String title;
  final String message;
  final String ctaLabel;

  static Future<void> show(BuildContext context, {required String title, required String message, String ctaLabel = 'Upgrade to Pro'}) {
    return AppBottomSheet.show(
      context: context,
      backgroundColor: AppDesignTokens.surfaceIvory,
      builder: (ctx) => SafeArea(child: UpgradePromptSheet(title: title, message: message, ctaLabel: ctaLabel)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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
                  height: 38,
                  width: 38,
                  decoration: BoxDecoration(
                    color: AppDesignTokens.champagneTint,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppDesignTokens.ctaTerracotta.withValues(alpha: 0.18)),
                  ),
                  child: const Icon(Icons.star_rounded, color: AppDesignTokens.ctaTerracotta, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: AppDesignTokens.textCharcoal),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(color: AppDesignTokens.textCharcoal, height: 1.35, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: AppSizing.primaryButtonHeight,
              child: FilledButton(
                onPressed: () {
                  context.pop();
                  context.push(AppRoutes.paywall);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignTokens.ctaTerracotta,
                  foregroundColor: scheme.onTertiary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: Text(
                  ctaLabel,
                  style: theme.textTheme.labelLarge?.copyWith(color: scheme.onTertiary, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => context.pop(),
                child: Text(
                  'Not now',
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
