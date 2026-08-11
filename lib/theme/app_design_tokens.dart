import 'package:flutter/material.dart';

/// Centralized, additive design tokens.
///
/// Note: This file is intentionally not referenced anywhere yet.
/// It only defines static constants to be used by future UI work.
abstract final class AppDesignTokens {
  // Colors
  static const Color backgroundSage = Color(0xFFE8EFEA);
  static const Color surfaceCream = Color(0xFFFBF9F4);
  static const Color ctaTerracotta = Color(0xFFD94A1E);
  static const Color deepForest = Color(0xFF1E3A2B);
  static const Color textCharcoal = Color(0xFF2C3531);

  // Spacing
  static const double spaceXS = 8;
  static const double spaceSM = 16;
  static const double spaceMD = 24;
  static const double spaceLG = 32;

  // Radii
  static const double radiusCard = 20;
  static const double radiusButton = 16;
  static const double radiusChip = 12;

  // Shadows (used for subtle “2–4dp” style depth on cream cards)
  static const List<BoxShadow> cardShadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 12,
      offset: Offset(0, 6),
    ),
  ];

  // Text styles
  static const TextStyle headline = TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: textCharcoal);
  static const TextStyle subheadline = TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textCharcoal);
  static const TextStyle body = TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: textCharcoal);
  static final TextStyle caption = TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textCharcoal.withValues(alpha: 0.7));
}
