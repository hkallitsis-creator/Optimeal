import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:optimeal/theme.dart';
import 'package:optimeal/theme/app_design_tokens.dart';

/// Post-cook shareable recap card — a growth/acquisition feature (see
/// CLAUDE.md roadmap item 7), shown after [WasteLedgerCelebrationSheet] and
/// [WhatYouLearnedSheet] close. Reuses data already produced by that same
/// flow (per-session rescued ingredients from `LedgerService.logCompletion`,
/// technique titles from the curriculum-matching pipeline) rather than
/// capturing anything new.
///
/// If there's nothing worth sharing (no ingredients rescued and no
/// technique matched — an edge case, not the common path), this sheet
/// closes itself silently, same pattern as [WhatYouLearnedSheet].
class PostCookShareCardSheet extends StatefulWidget {
  const PostCookShareCardSheet({
    super.key,
    required this.ingredientsRescued,
    required this.techniqueTitles,
  });

  final List<String> ingredientsRescued;
  final List<String> techniqueTitles;

  @override
  State<PostCookShareCardSheet> createState() => _PostCookShareCardSheetState();
}

class _PostCookShareCardSheetState extends State<PostCookShareCardSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  List<String> get _rescued =>
      widget.ingredientsRescued.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(growable: false);

  List<String> get _techniques =>
      widget.techniqueTitles.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(growable: false);

  String get _headline {
    final rescued = _rescued;
    final techniques = _techniques;
    if (rescued.isNotEmpty && techniques.isNotEmpty) {
      return 'I rescued ${rescued.length} ingredient${rescued.length == 1 ? '' : 's'} and learned to ${techniques.first.toLowerCase()}.';
    }
    if (rescued.isNotEmpty) {
      return 'I rescued ${rescued.length} ingredient${rescued.length == 1 ? '' : 's'} from going to waste.';
    }
    if (techniques.isNotEmpty) {
      return 'I learned ${techniques.first}.';
    }
    return 'Another zero-waste cook with Chef Harris.';
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/optimeal_recap_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles([XFile(file.path)], text: '$_headline 🍳 #OptiMeal');
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
      color: AppDesignTokens.surfaceCream,
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
                    color: AppDesignTokens.ctaTerracotta.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppDesignTokens.ctaTerracotta.withValues(alpha: 0.18)),
                  ),
                  child: const Icon(Icons.ios_share_rounded, color: AppDesignTokens.ctaTerracotta, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Share the win',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: AppDesignTokens.textCharcoal),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'A quick recap card, ready to post.',
              style: theme.textTheme.bodyMedium?.copyWith(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.78), fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Center(
              child: RepaintBoundary(
                key: _cardKey,
                child: _RecapCard(headline: _headline, rescued: _rescued, techniques: _techniques),
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
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.ios_share_rounded),
                label: Text(
                  _sharing ? 'Preparing…' : 'Share',
                  style: theme.textTheme.labelLarge?.copyWith(color: scheme.onTertiary, fontWeight: FontWeight.w900),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignTokens.ctaTerracotta,
                  foregroundColor: scheme.onTertiary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
                  style: theme.textTheme.labelLarge?.copyWith(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.65), fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The actual screenshot/share surface — kept visually separate from the
/// surrounding sheet chrome (buttons, "maybe later") so what gets captured
/// is clean and story/post-shaped, not an app screenshot.
class _RecapCard extends StatelessWidget {
  const _RecapCard({required this.headline, required this.rescued, required this.techniques});

  final String headline;
  final List<String> rescued;
  final List<String> techniques;

  @override
  Widget build(BuildContext context) {
    final previewIngredients = rescued.take(6).toList(growable: false);
    final overflowCount = rescued.length - previewIngredients.length;

    return Container(
      width: 320,
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppDesignTokens.deepForest, Color(0xFF14261B)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppDesignTokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.eco_rounded, color: AppDesignTokens.ctaTerracotta, size: 20),
              const SizedBox(width: 8),
              Text(
                'OPTIMEAL',
                style: TextStyle(
                  color: AppDesignTokens.surfaceCream.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            headline,
            style: const TextStyle(
              color: AppDesignTokens.surfaceCream,
              fontWeight: FontWeight.w900,
              fontSize: 22,
              height: 1.25,
            ),
          ),
          if (rescued.isNotEmpty) ...[
            const SizedBox(height: 18),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in previewIngredients) _RecapChip(label: item),
                if (overflowCount > 0) _RecapChip(label: '+$overflowCount more'),
              ],
            ),
          ],
          if (techniques.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline_rounded, color: AppDesignTokens.surfaceCream.withValues(alpha: 0.85), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    techniques.take(2).join(' · '),
                    style: TextStyle(
                      color: AppDesignTokens.surfaceCream.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          Text(
            'Zero-waste cooking, one recipe at a time.',
            style: TextStyle(
              color: AppDesignTokens.surfaceCream.withValues(alpha: 0.6),
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecapChip extends StatelessWidget {
  const _RecapChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceCream.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppDesignTokens.surfaceCream.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppDesignTokens.surfaceCream.withValues(alpha: 0.95),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
