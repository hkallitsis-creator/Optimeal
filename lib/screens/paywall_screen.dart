import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/services/entitlement_service.dart';
import 'package:optimeal/theme/app_design_tokens.dart';

enum PaywallPlan { monthly, annual }

class PaywallScreen extends StatefulWidget {
  /// If false, the close (X) button is hidden to force the user through
  /// the paywall on first run.
  final bool dismissible;

  const PaywallScreen({super.key, this.dismissible = true});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  PaywallPlan _selectedPlan = PaywallPlan.annual;
  bool _isPurchasing = false;

  // NOTE: placeholder variables (intentionally easy to A/B later).
  final double monthlyPrice = 15;

  double get annualPrice => monthlyPrice * 12 * 0.75;

  String get monthlyPriceLabel => '${monthlyPrice.toStringAsFixed(0)} CHF/month';

  String get annualPriceLabel => '${annualPrice.toStringAsFixed(0)} CHF/year';

  Future<void> _handlePurchase() async {
    // TODO: once real RevenueCat keys + store products exist, replace this
    // with an actual Purchases.purchasePackage(...) call. Until then this
    // flips the local mock entitlement flag so gating logic is testable
    // end to end — see entitlement_service.dart.
    if (_isPurchasing) return;
    setState(() => _isPurchasing = true);
    try {
      await EntitlementService.instance.setMockPro(true);
    } catch (e) {
      debugPrint('Failed to persist mock Pro entitlement: $e');
      // Non-fatal: allow navigation anyway.
    } finally {
      if (!mounted) return;
      setState(() => _isPurchasing = false);
      context.go(AppRoutes.home);
    }
  }

  void _handleClose() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final outlineSubtle = AppDesignTokens.textCharcoal.withValues(alpha: 0.18);

    return Scaffold(
      backgroundColor: AppDesignTokens.backgroundSage,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppDesignTokens.spaceLG,
                AppDesignTokens.spaceLG,
                AppDesignTokens.spaceLG,
                AppDesignTokens.spaceLG,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppDesignTokens.spaceXS),
                      const _PaywallHeader(),
                      const SizedBox(height: AppDesignTokens.spaceLG),
                      const _FeaturesCard(),
                      const SizedBox(height: AppDesignTokens.spaceLG),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 680;
                          final cards = [
                            _PricingCard(
                              title: 'Monthly',
                              priceLabel: monthlyPriceLabel,
                              subLabel: 'Billed monthly',
                              selected: _selectedPlan == PaywallPlan.monthly,
                              accent: false,
                              borderColor: _selectedPlan == PaywallPlan.monthly ? AppDesignTokens.ctaTerracotta : outlineSubtle,
                              onTap: () => setState(() => _selectedPlan = PaywallPlan.monthly),
                            ),
                            _PricingCard(
                              title: 'Annual',
                              priceLabel: annualPriceLabel,
                              subLabel: 'Save 25% vs monthly',
                              selected: _selectedPlan == PaywallPlan.annual,
                              accent: true,
                              borderColor: _selectedPlan == PaywallPlan.annual ? AppDesignTokens.ctaTerracotta : outlineSubtle,
                              onTap: () => setState(() => _selectedPlan = PaywallPlan.annual),
                            ),
                          ];

                          if (isWide) {
                            return Row(
                              children: [
                                Expanded(child: cards[0]),
                                const SizedBox(width: AppDesignTokens.spaceMD),
                                Expanded(child: cards[1]),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              cards[0],
                              const SizedBox(height: AppDesignTokens.spaceMD),
                              cards[1],
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: AppDesignTokens.spaceLG),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: _isPurchasing ? null : _handlePurchase,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppDesignTokens.ctaTerracotta,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusButton)),
                            splashFactory: NoSplash.splashFactory,
                            overlayColor: Colors.transparent,
                            textStyle: AppDesignTokens.subheadline.copyWith(color: Colors.white),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: _isPurchasing
                                ? const SizedBox(
                                    key: ValueKey('loading'),
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                                  )
                                : const Text(
                                    'Start Cooking Smarter',
                                    key: ValueKey('cta'),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppDesignTokens.spaceMD),
                      Text(
                        'Cancel anytime. No commitment, just fewer wilted vegetables.',
                        style: AppDesignTokens.caption.copyWith(height: 1.4),
                      ),
                      const SizedBox(height: AppDesignTokens.spaceXS),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () {
                            // Stub (no-op) for now.
                            if (kDebugMode) debugPrint('Restore purchases tapped (stub).');
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: AppDesignTokens.textCharcoal.withValues(alpha: 0.75),
                            splashFactory: NoSplash.splashFactory,
                            overlayColor: Colors.transparent,
                            textStyle: AppDesignTokens.caption,
                          ),
                          child: const Text('Restore purchases'),
                        ),
                      ),
                      const SizedBox(height: AppDesignTokens.spaceXS),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.dismissible)
              Positioned(
                left: AppDesignTokens.spaceXS / 2,
                top: AppDesignTokens.spaceXS / 2,
                child: IconButton(
                  onPressed: _handleClose,
                  icon: const Icon(Icons.close_rounded, color: AppDesignTokens.textCharcoal),
                  style: IconButton.styleFrom(
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PaywallHeader extends StatelessWidget {
  const _PaywallHeader();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceCream,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        border: Border.all(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.12), width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 10)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDesignTokens.spaceLG),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stop paying the food-waste tax.',
              style: AppDesignTokens.headline.copyWith(height: 1.15),
              textAlign: TextAlign.left,
            ),
            const SizedBox(height: AppDesignTokens.spaceMD),
            Text(
              'Swiss households waste 600+ CHF/year in food that never gets eaten.\nOptiMeal pays for itself in the first month by turning “what’s expiring” into dinner — and keeping your plan + list synced.',
              style: AppDesignTokens.body.copyWith(height: 1.5, color: AppDesignTokens.textCharcoal.withValues(alpha: 0.80)),
              textAlign: TextAlign.left,
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturesCard extends StatelessWidget {
  const _FeaturesCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceCream,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        border: Border.all(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.12), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDesignTokens.spaceMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Included with OptiMeal+', style: AppDesignTokens.subheadline.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppDesignTokens.spaceMD),
            const _FeatureRow(
              icon: Icons.auto_awesome_rounded,
              title: 'Fridge Clearer AI',
              subtitle: 'Turn “about to expire” into a real dinner — fast.',
            ),
            const SizedBox(height: AppDesignTokens.spaceSM),
            const _FeatureRow(
              icon: Icons.checklist_rounded,
              title: 'Weekly Planner',
              subtitle: 'Plan Mon–Sun and prep ingredients ahead of time.',
            ),
            const SizedBox(height: AppDesignTokens.spaceSM),
            const _FeatureRow(
              icon: Icons.timer_outlined,
              title: 'Full Cook Mode',
              subtitle: 'Live timers, checkboxes, and Swiss substitute guidance.',
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureRow({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppDesignTokens.ctaTerracotta.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip),
            border: Border.all(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.10)),
          ),
          child: Icon(icon, color: AppDesignTokens.ctaTerracotta, size: 22),
        ),
        const SizedBox(width: AppDesignTokens.spaceMD),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppDesignTokens.subheadline.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(subtitle, style: AppDesignTokens.body.copyWith(height: 1.45, color: AppDesignTokens.textCharcoal.withValues(alpha: 0.78))),
            ],
          ),
        ),
      ],
    );
  }
}

class _PricingCard extends StatelessWidget {
  final String title;
  final String priceLabel;
  final String subLabel;
  final bool selected;
  final bool accent;
  final Color borderColor;
  final VoidCallback onTap;

  const _PricingCard({
    required this.title,
    required this.priceLabel,
    required this.subLabel,
    required this.selected,
    required this.accent,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(AppDesignTokens.spaceMD),
          decoration: BoxDecoration(
            color: AppDesignTokens.surfaceCream,
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
            border: Border.all(color: borderColor, width: selected ? 1.6 : 1.0),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: selected ? 0.08 : 0.05), blurRadius: selected ? 18 : 14, offset: const Offset(0, 10)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: AppDesignTokens.subheadline.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: accent
                        ? Container(
                            key: const ValueKey('badge'),
                            padding: const EdgeInsets.symmetric(horizontal: AppDesignTokens.spaceSM, vertical: AppDesignTokens.spaceXS / 2),
                            decoration: BoxDecoration(
                              color: AppDesignTokens.ctaTerracotta,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Best Value',
                              style: AppDesignTokens.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 0.2),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('no-badge')),
                  ),
                ],
              ),
              const SizedBox(height: AppDesignTokens.spaceMD),
              Text(
                priceLabel,
                style: AppDesignTokens.headline.copyWith(fontWeight: FontWeight.w900, height: 1.1),
              ),
              const SizedBox(height: 6),
              Text(subLabel, style: AppDesignTokens.caption.copyWith(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.75))),
              const SizedBox(height: AppDesignTokens.spaceMD),
              Row(
                children: [
                  Icon(
                    selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                    color: selected ? AppDesignTokens.ctaTerracotta : AppDesignTokens.textCharcoal.withValues(alpha: 0.55),
                    size: 20,
                  ),
                  const SizedBox(width: AppDesignTokens.spaceXS),
                  Expanded(
                    child: Text(
                      selected ? 'Selected' : 'Tap to select',
                      style: AppDesignTokens.caption.copyWith(
                        fontWeight: FontWeight.w800,
                        color: selected ? AppDesignTokens.ctaTerracotta : AppDesignTokens.textCharcoal.withValues(alpha: 0.60),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
