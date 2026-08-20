import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/theme/app_design_tokens.dart';

/// Quiet home glyph for depth-2+ app bars.
///
/// The bottom nav bar is gone app-wide, so a screen reached *through* another
/// screen (Cook Mode, recipe details, the Weekly Planner's Fridge Clearer
/// picker) would otherwise need repeated back-taps to get out. Depth-1
/// screens — the ones opened straight off the Home hub — do NOT get this;
/// their back button already lands on Home.
///
/// Deliberately plain: small outlined icon, deep forest, no label, no
/// background container. It is not a CTA and must not read as one.
class HomeGlyphButton extends StatelessWidget {
  const HomeGlyphButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => context.go(AppRoutes.home),
      tooltip: 'Home', // SIGNED-CONTENT PLACEHOLDER
      visualDensity: VisualDensity.compact,
      icon: const Icon(
        Icons.home_outlined,
        size: 22,
        color: AppDesignTokens.deepForest,
      ),
    );
  }
}

/// Width to give [AppBar.leadingWidth] / [SliverAppBar.leadingWidth] when the
/// leading slot holds [BackWithHomeLeading]. The default leading slot is
/// 56dp — only wide enough for one button.
const double kBackWithHomeLeadingWidth = 104;

/// The depth-2+ app bar leading slot: the screen's existing back control with
/// the [HomeGlyphButton] beside it.
class BackWithHomeLeading extends StatelessWidget {
  const BackWithHomeLeading({super.key, required this.back});

  /// The screen's own back control, unchanged. Back-press semantics stay the
  /// property of the screen — this widget only sits a home glyph next to it.
  final Widget back;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: back),
        const HomeGlyphButton(),
      ],
    );
  }
}
