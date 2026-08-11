import 'package:flutter/material.dart';

import 'package:optimeal/theme/app_design_tokens.dart';

/// Simple branded avatar glyph used in place of the default profile icon.
///
/// This is intentionally “logo-like” (a chef / dining mark) rather than a
/// user photo, so it looks consistent even for anonymous/guest sessions.
class BrandedAvatarGlyph extends StatelessWidget {
  const BrandedAvatarGlyph({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        AppDesignTokens.ctaTerracotta,
        scheme.primary.withValues(alpha: 0.85),
      ],
    );

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: gradient,
          boxShadow: AppDesignTokens.cardShadow,
          border: Border.all(color: AppDesignTokens.surfaceCream.withValues(alpha: 0.9), width: 1.2),
        ),
        child: Center(
          child: Icon(
            Icons.restaurant_rounded,
            size: size * 0.58,
            color: AppDesignTokens.surfaceCream,
          ),
        ),
      ),
    );
  }
}
