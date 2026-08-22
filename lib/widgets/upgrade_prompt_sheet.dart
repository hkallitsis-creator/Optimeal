import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/services/upgrade_nudge_gate.dart';
import 'package:optimeal/theme.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/app_bottom_sheet.dart';

/// Shared upgrade-to-Pro nudge, used at the moments defined in CLAUDE.md's
/// "Monetization / paywall tier structure": the post-cook moment, the Fridge
/// Clearer weekly cap, and (once built) the Smart Suggestions locked preview.
///
/// # This is a plain kit sheet, not a celebration
///
/// It shipped styled as one — a star glyph over a "Nice cooking!" headline —
/// and fired mid-cook, which made a sales interstitial look like the app
/// congratulating you. The celebration styling is gone: ivory surface,
/// standard sheet chrome, no glyph, no congratulatory headline.
///
/// The CTA stays **terracotta**. Terracotta is "act now" and this is a sales
/// CTA; gold is the earned family and never goes on a sale. That is a signed
/// decision and is not the thing that was wrong here.
///
/// # It refuses to appear during a cook
///
/// [show] returns without presenting anything while
/// [UpgradeNudgeGate.isCookPathActive] — a sales sheet must never interrupt
/// the path from pre-cook to the post-cook verdict. The guard lives here, in
/// the one place every caller already goes through, rather than in each
/// caller, because a guard the caller has to remember is one the next caller
/// forgets.
class UpgradePromptSheet extends StatelessWidget {
  const UpgradePromptSheet({super.key, required this.title, required this.message, this.ctaLabel = 'Upgrade to Pro'});

  final String title;
  final String message;
  final String ctaLabel;

  static Future<void> show(BuildContext context, {required String title, required String message, String ctaLabel = 'Upgrade to Pro'}) async {
    // Never over an active cook. See the class doc.
    if (UpgradeNudgeGate.isCookPathActive) return;
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
            // No glyph. A star over a sales headline reads as the app
            // congratulating the user for being asked to pay.
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: AppDesignTokens.textCharcoal),
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
