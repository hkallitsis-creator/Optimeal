import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/app_bottom_sheet.dart';
import 'package:optimeal/widgets/technique_diagrams.dart';

/// Asset registry — key to (painter, display title). Only 3 keys have a
/// real built asset in this pilot phase: julienne (cut), pan_crowding and
/// cold_vs_hot_pan (technique). oil_depth, tray_spacing, staggered_adds,
/// and the other 15 cut keys are valid, declarable, parsed keys with no
/// entry here — [diagramFor] returns null for those, and callers render
/// nothing (no placeholder, no broken state), per instruction.
({CustomPainter painter, String title})? diagramFor(String key) {
  switch (key) {
    case 'julienne':
      return (painter: const JulienneCutPainter(), title: 'Julienne');
    case 'pan_crowding':
      return (painter: const PanCrowdingPainter(), title: 'Pan Crowding');
    case 'cold_vs_hot_pan':
      return (painter: const ColdVsHotPanPainter(), title: 'Cold vs. Hot Pan');
    default:
      return null;
  }
}

/// Tappable pill shown inline in a Cook Mode step, same interaction style
/// as the cut-definition pill and the sensory cue card — opens the diagram
/// in a bottom sheet on tap. Callers must check [diagramFor] themselves and
/// not build this widget at all when it returns null (see
/// one_pan_cooking_roadmap_screen.dart's call site) — this widget doesn't
/// self-guard, to keep "nothing built vs. nothing rendered" an explicit
/// decision at the call site, matching the rest of this codebase's pattern.
class DiagramPill extends StatelessWidget {
  const DiagramPill({super.key, required this.diagramKey, required this.title});

  final String diagramKey;
  final String title;

  void _showDiagram(BuildContext context) {
    final entry = diagramFor(diagramKey);
    if (entry == null) return;
    AppBottomSheet.show<void>(
      context: context,
      backgroundColor: AppDesignTokens.surfaceIvory,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(child: _DiagramDetailSheet(painter: entry.painter, title: entry.title)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _showDiagram(context),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppDesignTokens.deepForest.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppDesignTokens.deepForest.withValues(alpha: 0.20)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800, color: AppDesignTokens.deepForest),
            ),
            const SizedBox(width: 3),
            const Icon(Icons.image_outlined, size: 12, color: AppDesignTokens.deepForest),
          ],
        ),
      ),
    );
  }
}

class _DiagramDetailSheet extends StatelessWidget {
  const _DiagramDetailSheet({required this.painter, required this.title});

  final CustomPainter painter;
  final String title;

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
                    color: AppDesignTokens.deepForest.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppDesignTokens.deepForest.withValues(alpha: 0.18)),
                  ),
                  child: const Icon(Icons.image_outlined, color: AppDesignTokens.deepForest, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: AppDesignTokens.textCharcoal)),
                ),
                IconButton(
                  onPressed: () => context.pop(),
                  icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: CustomPaint(size: Size.infinite, painter: painter),
            ),
          ],
        ),
      ),
    );
  }
}
