import 'package:flutter/material.dart';

/// **Palette v1.2 (variant D) — the app's sole colour source.**
///
/// Signed 2026-08-21, swept app-wide 2026-08-22. Every colour the app draws
/// is defined here and nowhere else: `LightModeColors` / `DarkModeColors` in
/// `lib/theme.dart` are now thin Material-3 *role bindings* over these tokens
/// rather than a second palette, and no widget carries a `0xFF` literal. A
/// guard test (`test/theme/palette_token_guard_test.dart`) walks `lib/` and
/// fails the build if a literal reappears outside this file — the drift it
/// exists to prevent is exactly how two token sets came to disagree in the
/// first place.
///
/// ## The three semantic families
///
/// - **Terracotta = act now.** Primary CTAs, the one button on a screen that
///   moves the user forward. [ctaTerracotta] fills; [terracottaOnLight] is the
///   text/glyph weight (the fill value fails small-text contrast on ivory);
///   [champagneTint] is its background wash.
/// - **Sage = Chef Harris teaching.** [sageTeachingPanel] on cards, and only
///   on panels — sage on the canvas ([backgroundSage], [sageStripOnCanvas]) is
///   decorative and carries no teaching meaning.
/// - **Gold = earned.** Counted-verdict badges, rescue milestones, tier-ups,
///   the share accent. **Never** on CTAs, teaching panels, or large container
///   fills — glyphs, badges, thin borders and small text only. The Home rescue
///   strip stays sage, deliberately: it reports a running total, it is not an
///   earned moment.
abstract final class AppDesignTokens {
  // ───────────────────────────── Canvas & surfaces ─────────────────────────

  /// The app-wide canvas. Every screen's Scaffold reads this explicitly rather
  /// than relying on the theme default, so there is one source of truth.
  ///
  /// v1.2 deepened this from `0xFFC5D3C1`. The separation between the canvas
  /// and [sageStripOnCanvas] is the open device item on this swap — the two
  /// were further apart under the old, lighter canvas.
  static const Color backgroundSage = Color(0xFFB3C29A);

  /// Cards and bottom sheets. Ivory in v1.2, warmer than the cream
  /// (`0xFFFBF9F4`) it replaced — hence the rename from `surfaceCream`.
  static const Color surfaceIvory = Color(0xFFF8F3E9);

  /// The lighter surface for quiet list rows — My recipes' recently-cooked
  /// log, and anything else that must read as secondary to an ivory card
  /// without becoming a different material.
  static const Color quietRowSurface = Color(0xFFFDFBF5);

  /// Neutral (non-action) pills, chips and text inputs. The counterpart to
  /// [champagneTint]: same job, no "act now" meaning.
  static const Color neutralPillTint = Color(0xFFEFE8D8);

  // ─────────────────────────────── Act: terracotta ─────────────────────────

  /// Primary action. Fills only — see [terracottaOnLight] for text.
  static const Color ctaTerracotta = Color(0xFFC05C35);

  /// Terracotta as text or a glyph on a light surface. Darker than
  /// [ctaTerracotta] because the fill value fails small-text readability on
  /// ivory — the same fill-vs-text split gold uses.
  static const Color terracottaOnLight = Color(0xFFA44E2B);

  /// The terracotta background wash: heat pills, step chips, the Chef SOS
  /// surface, and the Weekly Planner's today row.
  static const Color champagneTint = Color(0xFFF7DBCB);

  // ──────────────────────────────── Teach: sage ────────────────────────────

  /// Chef Harris teaching content sitting **on a card**. Panels only — this
  /// token carries meaning, and using it decoratively spends it.
  static const Color sageTeachingPanel = Color(0xFFDDE6C6);

  /// Sage sitting directly **on the canvas** — today only the Home rescue
  /// strip. Deliberately a separate token from [sageTeachingPanel] even though
  /// v1.2 gives them the same value: the open device item is whether this
  /// separates enough from the deepened [backgroundSage], and if it has to
  /// move, it must move without dragging teaching panels with it.
  static const Color sageStripOnCanvas = Color(0xFFDDE6C6);

  // ──────────────────────────────── Earned: gold ───────────────────────────

  /// Gold as a fill or a border — badges and thin rules. Never a CTA, never a
  /// teaching panel, never a large container.
  static const Color goldEarnedFill = Color(0xFFEDA24E);

  /// Gold as a glyph or small text on a light surface. [goldEarnedFill] fails
  /// small-text contrast, exactly as [ctaTerracotta] does.
  ///
  /// This is the Weekly Planner's counted-cook check (was `cookedCountedGold`,
  /// same value).
  static const Color goldEarnedOnLight = Color(0xFFC77E1F);

  /// The pale wash behind an earned badge.
  static const Color goldEarnedBadgeTint = Color(0xFFFBEED8);

  // ────────────────────────────── Structure & text ─────────────────────────

  /// Titles, headers, selected states, and the "correct" line in technique
  /// diagrams. Not restated by v1.2 — carried forward unchanged.
  static const Color deepForest = Color(0xFF1E3A2B);

  /// One step darker than [deepForest]. Exists for the post-cook share card's
  /// gradient, which needs two stops of the same hue.
  static const Color deepForestShade = Color(0xFF14261B);

  /// Body text. Not restated by v1.2 — carried forward unchanged.
  static const Color textCharcoal = Color(0xFF2C3531);

  /// A completed cook that did **not** count toward the ledger. Deliberately a
  /// neutral rather than a red or an amber: not counting is not a failure, and
  /// it must not read as a dimmer gold.
  ///
  /// Outside the v1.2 table — provisionally signed, pending a device pass.
  static const Color cookedNeutralGray = Color(0xFF8B918E);

  // ───────────────────── Non-palette system colours ────────────────────────
  //
  // Material error roles and the (currently unreachable) dark scheme. These
  // are NOT part of palette v1.2 and have no semantic in it; they live here
  // only so that this file remains the single place a colour is defined. Do
  // not treat them as brand colours, and do not map brand semantics onto them.

  static const Color systemError = Color(0xFFBA1A1A);
  static const Color systemOnError = Color(0xFFFFFFFF);
  static const Color systemErrorContainer = Color(0xFFFFDAD6);
  static const Color systemOnErrorContainer = Color(0xFF410002);

  // Dark scheme. `main.dart` pins `themeMode: ThemeMode.light`, so none of
  // this is reachable today; v1.2 is a light-only palette and deliberately
  // says nothing about dark mode.
  static const Color darkBackground = Color(0xFF0F1714);
  static const Color darkSurface = Color(0xFF121C18);
  static const Color darkOnSurface = Color(0xFFEAF2ED);
  static const Color darkPrimary = Color(0xFFBFD3C9);
  static const Color darkPrimaryContainer = Color(0xFF22352C);
  static const Color darkSurfaceVariant = Color(0xFF18231F);
  static const Color darkOnSurfaceVariant = Color(0xFFB7C3BC);
  static const Color darkError = Color(0xFFFFB4AB);
  static const Color darkOnError = Color(0xFF690005);
  static const Color darkErrorContainer = Color(0xFF93000A);

  // ─────────────────────────────────── Spacing ─────────────────────────────
  static const double spaceXS = 8;
  static const double spaceSM = 16;
  static const double spaceMD = 24;
  static const double spaceLG = 32;

  // ──────────────────────────────────── Radii ──────────────────────────────
  static const double radiusCard = 20;
  static const double radiusButton = 16;
  static const double radiusChip = 12;

  // ─────────────────────────────────── Shadows ─────────────────────────────
  // Subtle "2–4dp" depth on ivory cards.
  static const List<BoxShadow> cardShadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 12,
      offset: Offset(0, 6),
    ),
  ];

  // ───────────────────────────────── Text styles ───────────────────────────
  static const TextStyle headline = TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: textCharcoal);
  static const TextStyle subheadline = TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textCharcoal);
  static const TextStyle body = TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: textCharcoal);
  static final TextStyle caption = TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textCharcoal.withValues(alpha: 0.7));
}
