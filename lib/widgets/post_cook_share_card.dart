import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:optimeal/theme.dart';
import 'package:optimeal/theme/app_design_tokens.dart';

/// Post-cook shareable recap card, shown after [WasteLedgerCelebrationSheet]
/// and [WhatYouLearnedSheet] close. Reuses data the same flow already
/// produced rather than capturing anything new.
///
/// # The branding gate — a standing rule, not a style choice
///
/// **No app name, wordmark, logo or link may appear on this card, in the
/// shared text, or in the shared file's name, until CH+EU trademark
/// clearance.** The layout keeps an empty branding slot so the name can drop
/// in the day clearance lands, without a redesign. Until then the card is
/// dish-and-story only.
///
/// This is enforced by `test/widgets/share_card_branding_guard_test.dart`,
/// which fails on any string matching `/optimeal|empyria|instinkt/i` anywhere
/// in this sheet's render tree. That test is permanent until the gate opens —
/// do not weaken it to make a change pass.
///
/// # Layout, per the signed spec
///
/// Photo slot (reserved, empty in v1) → dish name (large) → story line →
/// gold rescue chip + neutral technique chip → empty branding slot.
/// Card background is canvas sage with a thin gold border: gold is the
/// earned family, and a finished cook is an earned moment.
///
/// A cook that did not count toward the ledger can still be shared — it gets
/// the dish and the technique chip, and no rescue chip.
class PostCookShareCardSheet extends StatefulWidget {
  const PostCookShareCardSheet({
    super.key,
    required this.dishName,
    required this.ingredientsRescued,
    required this.techniqueTitles,
  });

  final String dishName;
  final List<String> ingredientsRescued;
  final List<String> techniqueTitles;

  @override
  State<PostCookShareCardSheet> createState() => _PostCookShareCardSheetState();
}

class _PostCookShareCardSheetState extends State<PostCookShareCardSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  List<String> get _rescued => widget.ingredientsRescued
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  List<String> get _techniques => widget.techniqueTitles
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  /// SIGNED-CONTENT PLACEHOLDER — the shared post text is Chef Harris
  /// authoring-batch content and has not been written.
  ///
  /// Composed only from fragments that ARE signed (the story line and the two
  /// chip patterns) so that nothing here is invented copy. It is also
  /// deliberately assembled from **noun forms**: the previous version wrote
  /// "learned to ${technique.toLowerCase()}", which on a technique named
  /// "Sautéing" produced *"learned to sautéing"*. Never conjugate a technique
  /// name — it is a noun, and the signed chip pattern already reads
  /// "sautéing, learned properly".
  String get _shareText {
    final parts = <String>[widget.dishName.trim()];
    if (_rescued.isNotEmpty) parts.add(kShareStoryLine);
    if (_techniques.isNotEmpty) parts.add(techniqueChipLabel(_techniques.first));
    return parts.where((p) => p.isNotEmpty).join(' — ');
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      // Filename carries no app name: many share targets show it to the
      // recipient, which would be branding on a public surface. Same gate as
      // the card itself.
      final file = File(
          '${dir.path}/recipe_recap_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);

      // No hashtag, no app name — see the branding gate on this class.
      await Share.shareXFiles([XFile(file.path)], text: _shareText);
    } catch (e) {
      debugPrint('Failed to share post-cook recap card: $e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_rescued.isEmpty && _techniques.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        context.pop();
      });
      return const SizedBox.shrink();
    }

    return Material(
      color: AppDesignTokens.surfaceIvory,
      child: SingleChildScrollView(
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
                    // Gold = earned: the share accent is a named gold moment.
                    color: AppDesignTokens.goldEarnedBadgeTint,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppDesignTokens.goldEarnedFill),
                  ),
                  child: const Icon(Icons.ios_share_rounded,
                      color: AppDesignTokens.goldEarnedOnLight, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    // SIGNED-CONTENT PLACEHOLDER
                    'Share the win',
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppDesignTokens.textCharcoal),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              // SIGNED-CONTENT PLACEHOLDER
              'A quick recap card, ready to post.',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppDesignTokens.textCharcoal.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Center(
              child: RepaintBoundary(
                key: _cardKey,
                child: _RecapCard(
                  dishName: widget.dishName,
                  rescued: _rescued,
                  techniques: _techniques,
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: AppSizing.primaryButtonHeight,
              child: FilledButton.icon(
                onPressed: _sharing ? null : _share,
                icon: _sharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.ios_share_rounded),
                label: Text(
                  _sharing ? 'Preparing…' : 'Share',
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onTertiary, fontWeight: FontWeight.w900),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignTokens.ctaTerracotta,
                  foregroundColor: scheme.onTertiary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => context.pop(),
                child: Text(
                  'Maybe later',
                  style: theme.textTheme.labelLarge?.copyWith(
                      color:
                          AppDesignTokens.textCharcoal.withValues(alpha: 0.65),
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The signed story line. Brags resourcefulness, not app usage — which is
/// also why it survives the branding gate untouched.
const String kShareStoryLine = 'Cooked from what was already in my fridge.';

/// The signed rescue-chip pattern.
String rescueChipLabel(int count) =>
    '$count ingredient${count == 1 ? '' : 's'} rescued';

/// The signed technique-chip pattern: the technique NAME followed by
/// ", learned properly". The name is a noun and is never conjugated — see
/// [_PostCookShareCardSheetState._shareText].
String techniqueChipLabel(String technique) =>
    '${technique.trim().toLowerCase()}, learned properly';

/// The actual capture surface, kept visually separate from the sheet chrome
/// so what gets shared is story-shaped, not an app screenshot.
class _RecapCard extends StatelessWidget {
  const _RecapCard({
    required this.dishName,
    required this.rescued,
    required this.techniques,
  });

  final String dishName;
  final List<String> rescued;
  final List<String> techniques;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
      decoration: BoxDecoration(
        // Canvas sage with a thin gold border — earned framing.
        color: AppDesignTokens.backgroundSage,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppDesignTokens.goldEarnedFill, width: 1.5),
        boxShadow: AppDesignTokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Photo slot — DEFERRED, reserved on purpose ──────────────────
          // No camera step in v1 (permissions, storage and layout scope).
          // The slot stays in the layout so a photo can be added on tester
          // signal without a redesign. It renders nothing today.
          const SizedBox.shrink(),

          Text(
            dishName,
            style: const TextStyle(
              color: AppDesignTokens.textCharcoal,
              fontWeight: FontWeight.w900,
              fontSize: 24,
              height: 1.2,
            ),
          ),

          if (rescued.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              kShareStoryLine,
              style: TextStyle(
                color: AppDesignTokens.textCharcoal.withValues(alpha: 0.82),
                fontWeight: FontWeight.w600,
                fontSize: 14,
                height: 1.3,
              ),
            ),
          ],

          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (rescued.isNotEmpty)
                _RecapChip(
                  label: rescueChipLabel(rescued.length),
                  fill: AppDesignTokens.goldEarnedBadgeTint,
                  textColor: AppDesignTokens.goldEarnedOnLight,
                  borderColor: AppDesignTokens.goldEarnedFill,
                ),
              if (techniques.isNotEmpty)
                _RecapChip(
                  label: techniqueChipLabel(techniques.first),
                  fill: AppDesignTokens.surfaceIvory,
                  textColor: AppDesignTokens.textCharcoal,
                  borderColor:
                      AppDesignTokens.textCharcoal.withValues(alpha: 0.15),
                ),
            ],
          ),

          // ── Branding slot — EMPTY UNTIL TRADEMARK CLEARANCE ─────────────
          // App name and link land here, and nowhere else, the day CH+EU
          // clearance comes through. Ships empty. Do not fill this in
          // without checking the gate — there is a test on it.
          const SizedBox(height: 18),
          const SizedBox(height: 0, width: double.infinity),
        ],
      ),
    );
  }
}

class _RecapChip extends StatelessWidget {
  const _RecapChip({
    required this.label,
    required this.fill,
    required this.textColor,
    required this.borderColor,
  });

  final String label;
  final Color fill;
  final Color textColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
    );
  }
}
