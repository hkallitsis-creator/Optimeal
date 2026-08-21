import 'package:flutter/material.dart';
import 'package:optimeal/models/technique_lesson.dart' as models;
import 'package:optimeal/theme/app_design_tokens.dart';

/// Compact, inline-friendly educational callout card for technique “matrix” tips.
///
/// This widget is purely presentational. It renders whatever fields are present on
/// the provided [CulinaryMatrixCard] model and has zero dependencies on app state.
class CulinaryMatrixCard extends StatelessWidget {
  final models.CulinaryMatrixCard matrix;

  const CulinaryMatrixCard({super.key, required this.matrix});

  bool get _hasHeat => matrix.heatCue.trim().isNotEmpty;
  bool get _hasTiming => matrix.timingNote.trim().isNotEmpty;
  bool get _hasKnife => (matrix.knifeCutSpec ?? '').trim().isNotEmpty;
  bool get _hasRatio => (matrix.ratioSummary ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final borderColor = AppDesignTokens.textCharcoal.withValues(alpha: 0.10);
    final calloutLabelStyle = AppDesignTokens.caption.copyWith(fontWeight: FontWeight.w700);
    final calloutTextStyle = AppDesignTokens.body;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceIvory,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: AppDesignTokens.cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDesignTokens.spaceSM),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MatrixTitleRow(title: matrix.title, showHeatIcon: _hasHeat, showKnifeIcon: _hasKnife),
            if (_hasRatio) ...[
              const SizedBox(height: 10),
              _RatioSummaryBadge(text: matrix.ratioSummary!.trim()),
            ],
            if (_hasHeat || _hasTiming || _hasKnife) ...[
              const SizedBox(height: 12),
              if (_hasHeat)
                _MatrixCalloutRow(
                  emoji: '🔥',
                  label: 'Heat',
                  text: matrix.heatCue.trim(),
                  labelStyle: calloutLabelStyle,
                  textStyle: calloutTextStyle,
                ),
              if (_hasTiming)
                _MatrixCalloutRow(
                  emoji: '⏱',
                  label: 'Timing',
                  text: matrix.timingNote.trim(),
                  labelStyle: calloutLabelStyle,
                  textStyle: calloutTextStyle,
                ),
              if (_hasKnife)
                _MatrixCalloutRow(
                  emoji: '🔪',
                  label: 'Cut',
                  text: matrix.knifeCutSpec!.trim(),
                  labelStyle: calloutLabelStyle,
                  textStyle: calloutTextStyle,
                ),
            ],
            const SizedBox(height: 12),
            _WhyThisWorksFooter(text: matrix.whyThisWorks.trim()),
          ],
        ),
      ),
    );
  }
}

class _MatrixTitleRow extends StatelessWidget {
  final String title;
  final bool showHeatIcon;
  final bool showKnifeIcon;

  const _MatrixTitleRow({required this.title, required this.showHeatIcon, required this.showKnifeIcon});

  @override
  Widget build(BuildContext context) {
    final icon = showHeatIcon
        ? Icons.local_fire_department_rounded
        : (showKnifeIcon ? Icons.content_cut_rounded : Icons.lightbulb_rounded);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppDesignTokens.ctaTerracotta),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: AppDesignTokens.subheadline.copyWith(fontWeight: FontWeight.w800))),
      ],
    );
  }
}

class _RatioSummaryBadge extends StatelessWidget {
  final String text;

  const _RatioSummaryBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    final bg = AppDesignTokens.ctaTerracotta.withValues(alpha: 0.12);
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            text,
            style: AppDesignTokens.caption.copyWith(
              color: AppDesignTokens.textCharcoal,
              fontFamily: 'monospace',
              letterSpacing: 0.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _MatrixCalloutRow extends StatelessWidget {
  final String emoji;
  final String label;
  final String text;
  final TextStyle labelStyle;
  final TextStyle textStyle;

  const _MatrixCalloutRow({
    required this.emoji,
    required this.label,
    required this.text,
    required this.labelStyle,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14, height: 1.2)),
          const SizedBox(width: 10),
          Text('$label:', style: labelStyle),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: textStyle)),
        ],
      ),
    );
  }
}

class _WhyThisWorksFooter extends StatelessWidget {
  final String text;

  const _WhyThisWorksFooter({required this.text});

  @override
  Widget build(BuildContext context) {
    final bg = AppDesignTokens.backgroundSage;
    final border = AppDesignTokens.textCharcoal.withValues(alpha: 0.08);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Why This Works', style: AppDesignTokens.caption.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              text,
              style: AppDesignTokens.caption.copyWith(fontStyle: FontStyle.italic, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
