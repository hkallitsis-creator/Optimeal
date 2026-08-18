import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:optimeal/services/confidence_climb_service.dart';
import 'package:optimeal/theme.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/curriculum_drawer_content.dart';

/// A compact recap sheet shown after Cook Mode when a recipe includes
/// curriculum drawer keys.
///
/// If no keys resolve (common for recipes generated before this feature, or
/// recipes whose title/prompt happened to match nothing), this sheet closes
/// itself silently so the user never sees a blank bottom sheet.
class WhatYouLearnedSheet extends StatefulWidget {
  const WhatYouLearnedSheet({
    super.key,
    required this.curriculumLessonIds,
    this.confidenceLine,
    this.repeatTechniqueIds = const <String>{},
  });

  final List<String> curriculumLessonIds;

  /// Optional Confidence Climb line (e.g. "3rd time this month using
  /// Braising — you're building real knife + heat control."). Deliberately
  /// rare — only set when [ConfidenceClimbService] finds a real signal, not
  /// shown on every cook. See CLAUDE.md Retention Features Backlog item 2.
  final String? confidenceLine;

  /// Subset of [curriculumLessonIds] the user has completed before —
  /// exactly these get the "Are you comfortable with this technique?"
  /// question appended (docs/decisions_2026-08-17.md item 7). A technique's
  /// first-ever completion shows no question, celebration only. The caller
  /// (OnePanCookingRoadmapScreen) is expected to have already excluded any
  /// already-comfortable technique from [curriculumLessonIds] entirely.
  final Set<String> repeatTechniqueIds;

  @override
  State<WhatYouLearnedSheet> createState() => _WhatYouLearnedSheetState();
}

class _WhatYouLearnedSheetState extends State<WhatYouLearnedSheet> {
  final _confidenceClimbService = ConfidenceClimbService();

  /// Technique ids answered during this sheet's lifetime (either option) —
  /// swaps the question for a short acknowledgement so it can't be
  /// double-tapped.
  final Set<String> _answered = <String>{};

  Future<void> _answer(String techniqueId, {required bool comfortable}) async {
    if (comfortable) {
      await _confidenceClimbService.markComfortable(techniqueId);
    }
    if (!mounted) return;
    setState(() => _answered.add(techniqueId));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final curriculumLessonIds = widget.curriculumLessonIds;

    debugPrint('WhatYouLearnedSheet: received ids=$curriculumLessonIds');

    final matchedLessons = resolveDrawerEntries(curriculumLessonIds).toList(growable: false);
    debugPrint('WhatYouLearnedSheet: received ids=$curriculumLessonIds, resolved ${matchedLessons.length} lessons');

    final resolved = matchedLessons.take(2).toList(growable: false);
    if (resolved.isEmpty) {
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
                    color: AppDesignTokens.deepForest.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppDesignTokens.deepForest.withValues(alpha: 0.18)),
                  ),
                  child: const Icon(Icons.lightbulb_outline_rounded, color: AppDesignTokens.deepForest, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'What you learned',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: AppDesignTokens.textCharcoal),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'A couple technique notes you can reuse next time.',
              style: theme.textTheme.bodyMedium?.copyWith(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.78), height: 1.35, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            for (final entry in resolved) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DrawerCard(entry: entry),
              ),
              if (widget.repeatTechniqueIds.contains(entry.key))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ConfidenceQuestionCard(
                    answered: _answered.contains(entry.key),
                    onAnswer: (comfortable) => _answer(entry.key, comfortable: comfortable),
                  ),
                ),
            ],
            if (widget.confidenceLine != null) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppDesignTokens.deepForest.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppDesignTokens.deepForest.withValues(alpha: 0.16)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.trending_up_rounded, size: 18, color: AppDesignTokens.deepForest),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.confidenceLine!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppDesignTokens.deepForest,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            Divider(height: 1, thickness: 1, color: scheme.outline.withValues(alpha: 0.12)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: AppSizing.primaryButtonHeight,
              child: FilledButton(
                onPressed: () => context.pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignTokens.ctaTerracotta,
                  foregroundColor: scheme.onTertiary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: Text(
                  'Got it',
                  style: theme.textTheme.labelLarge?.copyWith(color: scheme.onTertiary, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "Are you comfortable with this technique?" question
/// (docs/decisions_2026-08-17.md item 7 — verbatim wording, both options).
/// Swaps to a short acknowledgement once answered, so it can't be
/// double-tapped within the same sheet.
class _ConfidenceQuestionCard extends StatelessWidget {
  const _ConfidenceQuestionCard({required this.answered, required this.onAnswer});

  final bool answered;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceCream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.12)),
      ),
      child: answered
          ? Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 18, color: AppDesignTokens.deepForest),
                const SizedBox(width: 8),
                Text('Thanks — noted.', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you comfortable with this technique?',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: AppDesignTokens.textCharcoal),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => onAnswer(true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppDesignTokens.deepForest,
                          side: BorderSide(color: AppDesignTokens.deepForest.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text("Yes, it's automatic now", textAlign: TextAlign.center),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => onAnswer(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppDesignTokens.textCharcoal.withValues(alpha: 0.78),
                          side: BorderSide(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.22)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Not yet, still takes concentration', textAlign: TextAlign.center),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
