import 'dart:math' as math;

import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:optimeal/theme/app_design_tokens.dart';

/// Lightweight lesson data model for the [TechniqueLessonSheet].
///
/// This is intentionally UI-focused and self-contained so it can be used
/// without touching any other app models/services. A lesson may have
/// photos, an external video link, both, or neither — this sheet must
/// render sensibly in every case (see CLAUDE.md "Curriculum content
/// strategy"), falling back to text-only when there's no visual content.
class TechniqueLesson {
  const TechniqueLesson({
    required this.title,
    required this.category,
    this.photoUrls = const <String>[],
    this.externalVideoUrl,
    required this.description,
    this.breakdownSteps = const <TechniqueBreakdownStep>[],
  });

  final String title;
  final String category;
  final List<String> photoUrls;

  /// Optional, separately-curated link to a creator's video. Not built out
  /// with real content yet — just a first-class field to render when
  /// populated later.
  final String? externalVideoUrl;
  final String description;
  final List<TechniqueBreakdownStep> breakdownSteps;

  bool get hasPhotos => photoUrls.isNotEmpty;
  bool get hasExternalVideo => (externalVideoUrl ?? '').trim().isNotEmpty;
}

class TechniqueBreakdownStep {
  const TechniqueBreakdownStep({required this.label, required this.detail});

  final String label;
  final String detail;
}

/// Reusable draggable modal sheet for a technique lesson's photos, optional
/// external video link, and breakdown steps.
class TechniqueLessonSheet extends StatelessWidget {
  const TechniqueLessonSheet({super.key, required this.lesson});

  final TechniqueLesson lesson;

  static Future<T?> show<T>(BuildContext context, TechniqueLesson lesson) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => TechniqueLessonSheet(lesson: lesson),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: DecoratedBox(
            decoration: const BoxDecoration(color: AppDesignTokens.surfaceIvory),
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.zero,
              children: [
                _LessonHeader(lesson: lesson),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppDesignTokens.spaceMD,
                    AppDesignTokens.spaceSM,
                    AppDesignTokens.spaceMD,
                    AppDesignTokens.spaceMD,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(lesson.title, style: AppDesignTokens.headline),
                      const SizedBox(height: AppDesignTokens.spaceSM),
                      _CategoryPill(category: lesson.category),
                      const SizedBox(height: AppDesignTokens.spaceSM),
                      Text(lesson.description, style: AppDesignTokens.body),
                      if (lesson.hasExternalVideo) ...[
                        const SizedBox(height: AppDesignTokens.spaceSM),
                        _ExternalVideoLink(url: lesson.externalVideoUrl!),
                      ],
                      const SizedBox(height: AppDesignTokens.spaceMD),
                      Text('Technique Breakdown', style: AppDesignTokens.subheadline),
                      const SizedBox(height: AppDesignTokens.spaceSM),
                      if (lesson.breakdownSteps.isEmpty)
                        Text('No breakdown steps yet.', style: AppDesignTokens.caption)
                      else
                        ...List.generate(
                          lesson.breakdownSteps.length,
                          (index) => Padding(
                            padding: const EdgeInsets.only(bottom: AppDesignTokens.spaceSM),
                            child: _BreakdownRow(index: index, step: lesson.breakdownSteps[index]),
                          ),
                        ),
                      const SizedBox(height: AppDesignTokens.spaceLG),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Header area: a swipeable photo sequence when photos exist, otherwise a
/// plain gradient card — never a video player, since nothing here is video.
class _LessonHeader extends StatefulWidget {
  const _LessonHeader({required this.lesson});

  final TechniqueLesson lesson;

  @override
  State<_LessonHeader> createState() => _LessonHeaderState();
}

class _LessonHeaderState extends State<_LessonHeader> {
  final PageController _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double computedHeight = constraints.maxWidth * (16 / 9);
        final double height = math.min(460, computedHeight);

        return SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (lesson.hasPhotos)
                PageView.builder(
                  controller: _pageController,
                  itemCount: lesson.photoUrls.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) => Image.network(
                    lesson.photoUrls[i],
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _PlaceholderBackground(lesson: lesson),
                  ),
                )
              else
                _PlaceholderBackground(lesson: lesson),
              if (lesson.photoUrls.length > 1)
                Positioned(
                  bottom: AppDesignTokens.spaceMD,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      lesson.photoUrls.length,
                      (i) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _page ? 16 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppDesignTokens.surfaceIvory.withValues(alpha: i == _page ? 0.95 : 0.5),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppDesignTokens.textCharcoal.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => context.pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        Icons.close_rounded,
                        color: AppDesignTokens.textCharcoal.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Fallback header when there are no real photos to show — a plain gradient
/// card, intentionally not implying video (no play button) unless there's
/// an actual external video link to open.
class _PlaceholderBackground extends StatelessWidget {
  const _PlaceholderBackground({required this.lesson});

  final TechniqueLesson lesson;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppDesignTokens.backgroundSage,
            AppDesignTokens.ctaTerracotta.withValues(alpha: 0.16),
          ],
        ),
      ),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppDesignTokens.surfaceIvory.withValues(alpha: 0.6),
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Icon(
              lesson.hasExternalVideo ? Icons.play_arrow_rounded : Icons.menu_book_rounded,
              size: 48,
              color: AppDesignTokens.textCharcoal,
            ),
          ),
        ),
      ),
    );
  }
}

class _ExternalVideoLink extends StatelessWidget {
  const _ExternalVideoLink({required this.url});

  final String url;

  Future<void> _open() async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppDesignTokens.backgroundSage,
      borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip),
        onTap: _open,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.play_circle_outline_rounded, color: AppDesignTokens.deepForest, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Watch the full video',
                  style: AppDesignTokens.body.copyWith(fontWeight: FontWeight.w700, color: AppDesignTokens.deepForest),
                ),
              ),
              const Icon(Icons.open_in_new_rounded, color: AppDesignTokens.deepForest, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppDesignTokens.ctaTerracotta,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          category,
          style: AppDesignTokens.caption.copyWith(color: AppDesignTokens.surfaceIvory),
        ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.index, required this.step});

  final int index;
  final TechniqueBreakdownStep step;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceIvory,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        border: Border.all(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDesignTokens.spaceSM),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(color: AppDesignTokens.ctaTerracotta, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                style: AppDesignTokens.caption.copyWith(
                  color: AppDesignTokens.surfaceIvory,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppDesignTokens.spaceSM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.label, style: AppDesignTokens.subheadline.copyWith(fontSize: 16)),
                  const SizedBox(height: AppDesignTokens.spaceXS),
                  Text(step.detail, style: AppDesignTokens.body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
