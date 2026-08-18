import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/models/curriculum_library.dart';
import 'package:optimeal/models/technique_lesson.dart' as models;
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/technique_lesson_sheet.dart' as sheet;

class TechniquesMediaScreen extends StatefulWidget {
  const TechniquesMediaScreen({super.key});

  @override
  State<TechniquesMediaScreen> createState() => _TechniquesMediaScreenState();
}

class _TechniquesMediaScreenState extends State<TechniquesMediaScreen> {
  static const List<models.TechniqueCategory> _categories = [
    models.TechniqueCategory.matrixesRatios,
    models.TechniqueCategory.knifeHeatManagement,
    models.TechniqueCategory.europeanSubstitutes,
    models.TechniqueCategory.zeroWasteCrisperHacks,
  ];

  late models.TechniqueCategory _selectedCategory = _categories.first;

  final List<models.TechniqueLesson> _lessons = CurriculumLibrary.lessons;

  void _openTechniqueSheet(BuildContext context, models.TechniqueLesson lesson) {
    debugPrint('Open technique sheet: ${lesson.title}');
    sheet.TechniqueLessonSheet.show(
      context,
      sheet.TechniqueLesson(
        title: lesson.title,
        category: _categoryLabel(lesson.category),
        photoUrls: lesson.photoUrls,
        externalVideoUrl: lesson.externalVideoUrl,
        description: lesson.shortDescription,
        breakdownSteps: lesson.breakdownSteps
            .map((s) => sheet.TechniqueBreakdownStep(label: s.label, detail: s.detail))
            .toList(growable: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double pagePadding = AppDesignTokens.spaceSM.toDouble();
    final double gridGap = AppDesignTokens.spaceSM.toDouble();
    final lessons = _lessons.where((l) => l.category == _selectedCategory).toList(growable: false);

    return Scaffold(
      backgroundColor: AppDesignTokens.backgroundSage,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.home),
          tooltip: 'Home',
          icon: Container(
            padding: const EdgeInsets.all(AppDesignTokens.spaceXS),
            decoration: BoxDecoration(
              color: AppDesignTokens.surfaceCream.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip),
              border: Border.all(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.12)),
            ),
            child: const Icon(Icons.arrow_back, color: AppDesignTokens.textCharcoal),
          ),
        ),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pagePadding, pagePadding, pagePadding, 0),
              sliver: SliverToBoxAdapter(child: _HeaderSection()),
            ),
            SliverToBoxAdapter(
              child: SizedBox(height: AppDesignTokens.spaceMD.toDouble()),
            ),
            SliverToBoxAdapter(
              child: _CategoryChipsRow(
                categories: _categories,
                selectedCategory: _selectedCategory,
                onSelected: (value) => setState(() => _selectedCategory = value),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(height: AppDesignTokens.spaceMD.toDouble()),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pagePadding, 0, pagePadding, pagePadding),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.crossAxisExtent;
                  int crossAxisCount = 2;
                  if (width >= 980) {
                    crossAxisCount = 4;
                  } else if (width >= 680) {
                    crossAxisCount = 3;
                  }

                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: gridGap,
                      crossAxisSpacing: gridGap,
                      childAspectRatio: 0.56,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final lesson = lessons[index];
                        return TechniqueLessonCard(
                          lesson: lesson,
                          onTap: () => _openTechniqueSheet(context, lesson),
                        );
                      },
                      childCount: lessons.length,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Chef Harris — Techniques & Media', style: AppDesignTokens.headline),
        SizedBox(height: AppDesignTokens.spaceXS.toDouble()),
        Text('Learn the ratios and instincts, not just the recipe.', style: AppDesignTokens.body),
      ],
    );
  }
}

class _CategoryChipsRow extends StatelessWidget {
  const _CategoryChipsRow({
    required this.categories,
    required this.selectedCategory,
    required this.onSelected,
  });

  final List<models.TechniqueCategory> categories;
  final models.TechniqueCategory selectedCategory;
  final ValueChanged<models.TechniqueCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final double horizontalPad = AppDesignTokens.spaceSM.toDouble();

    return SizedBox(
      // Allow long labels (e.g., "Knife Skills & Heat Management") to wrap to
      // two lines instead of truncating mid-word, while preserving styling and
      // selection behavior.
      height: 56,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: horizontalPad),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (context, index) => SizedBox(width: AppDesignTokens.spaceXS.toDouble()),
        itemBuilder: (context, index) {
          final category = categories[index];
          final label = _categoryLabel(category);
          final bool selected = category == selectedCategory;

          final Color bg = selected ? AppDesignTokens.ctaTerracotta : AppDesignTokens.surfaceCream;
          final Color fg = selected ? AppDesignTokens.surfaceCream : AppDesignTokens.textCharcoal;
          final Color border = AppDesignTokens.textCharcoal.withValues(alpha: selected ? 0 : 0.16);

          return GestureDetector(
            onTap: () => onSelected(category),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.symmetric(
                horizontal: AppDesignTokens.spaceSM.toDouble(),
                vertical: (AppDesignTokens.spaceXS / 2).toDouble(),
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip.toDouble()),
                border: Border.all(color: border, width: 1),
              ),
              child: Center(
                child: Text(
                  label,
                  style: AppDesignTokens.body.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    height: 1.05,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

enum TechniqueGradientSeed { terracotta, sage, charcoal }

/// What the thumbnail should visually promise — must match what
/// [TechniqueLessonSheet] actually shows when tapped, since nothing here is
/// video-first anymore (see CLAUDE.md "Curriculum content strategy").
enum _ThumbnailMode { photo, externalVideo, textOnly }

_ThumbnailMode _modeForLesson(models.TechniqueLesson lesson) {
  if (lesson.photoUrls.isNotEmpty) return _ThumbnailMode.photo;
  if ((lesson.externalVideoUrl ?? '').trim().isNotEmpty) return _ThumbnailMode.externalVideo;
  return _ThumbnailMode.textOnly;
}

class TechniqueLessonCard extends StatelessWidget {
  const TechniqueLessonCard({super.key, required this.lesson, required this.onTap});

  final models.TechniqueLesson lesson;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double radius = AppDesignTokens.radiusButton.toDouble();
    // Keep the card's overall size (grid + aspect ratio) unchanged, but make the
    // internal layout flexible so the bottom text area never overflows.
    final double horizontalPad = AppDesignTokens.spaceSM.toDouble();
    final double verticalPad = AppDesignTokens.spaceXS.toDouble();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppDesignTokens.surfaceCream,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.10), width: 1),
          boxShadow: AppDesignTokens.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TechniqueThumbnail(
                  mode: _modeForLesson(lesson),
                  photoUrl: lesson.photoUrls.isEmpty ? null : lesson.photoUrls.first,
                  durationLabel: _durationLabelFromSeconds(lesson.durationSeconds),
                  gradientSeed: _gradientSeedForLesson(lesson),
                ),
              ),
              Flexible(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(horizontalPad, verticalPad, horizontalPad, verticalPad),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(
                          lesson.title,
                          style: AppDesignTokens.subheadline.copyWith(height: 1.15, fontSize: 15),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(height: (AppDesignTokens.spaceXS / 2).toDouble()),
                      Text(
                        _categoryLabel(lesson.category),
                        style: AppDesignTokens.caption.copyWith(fontSize: 12, height: 1.1),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TechniqueThumbnail extends StatelessWidget {
  const _TechniqueThumbnail({
    required this.mode,
    required this.photoUrl,
    required this.durationLabel,
    required this.gradientSeed,
  });

  final _ThumbnailMode mode;
  final String? photoUrl;
  final String durationLabel;
  final TechniqueGradientSeed gradientSeed;

  @override
  Widget build(BuildContext context) {
    final gradient = _gradientForSeed(gradientSeed);

    // Icon promises exactly what the tap will open: a play icon only when
    // there's a real external video link, a book icon for text-only
    // lessons. Never assume video is present (see CLAUDE.md "Curriculum
    // content strategy").
    final IconData badgeIcon = switch (mode) {
      _ThumbnailMode.photo => Icons.photo_library_rounded,
      _ThumbnailMode.externalVideo => Icons.play_arrow_rounded,
      _ThumbnailMode.textOnly => Icons.menu_book_rounded,
    };
    // Duration only means something when there's timed media (a video) to
    // watch — hide it for photo sequences and text-only lessons.
    final bool showDuration = mode == _ThumbnailMode.externalVideo;

    // IMPORTANT: Don't use a fixed AspectRatio here. The grid tile already has a
    // fixed height, and forcing 9:16 causes the card contents to exceed the tile
    // height, triggering "BOTTOM OVERFLOWED".
    return Stack(
      fit: StackFit.expand,
      children: [
        if (mode == _ThumbnailMode.photo && photoUrl != null)
          Image.network(
            photoUrl!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
          )
        else
          DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
        Center(
          child: Container(
            padding: EdgeInsets.all((AppDesignTokens.spaceXS / 1.4).toDouble()),
            decoration: BoxDecoration(
              color: AppDesignTokens.textCharcoal.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(badgeIcon, size: 30, color: AppDesignTokens.surfaceCream),
          ),
        ),
        if (showDuration)
          Positioned(
            top: (AppDesignTokens.spaceXS / 1.2).toDouble(),
            right: (AppDesignTokens.spaceXS / 1.2).toDouble(),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: (AppDesignTokens.spaceXS / 1.4).toDouble(),
                vertical: (AppDesignTokens.spaceXS / 1.8).toDouble(),
              ),
              decoration: BoxDecoration(
                color: AppDesignTokens.textCharcoal.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip.toDouble()),
              ),
              child: Text(
                durationLabel,
                style: AppDesignTokens.caption.copyWith(
                  color: AppDesignTokens.surfaceCream,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  height: 1.0,
                ),
              ),
            ),
          ),
      ],
    );
  }

  LinearGradient _gradientForSeed(TechniqueGradientSeed seed) {
    switch (seed) {
      case TechniqueGradientSeed.terracotta:
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppDesignTokens.ctaTerracotta.withValues(alpha: 0.35),
            AppDesignTokens.textCharcoal.withValues(alpha: 0.10),
          ],
        );
      case TechniqueGradientSeed.sage:
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppDesignTokens.backgroundSage,
            AppDesignTokens.textCharcoal.withValues(alpha: 0.12),
          ],
        );
      case TechniqueGradientSeed.charcoal:
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppDesignTokens.textCharcoal.withValues(alpha: 0.35),
            AppDesignTokens.backgroundSage,
          ],
        );
    }
  }
}

String _categoryLabel(models.TechniqueCategory category) {
  switch (category) {
    case models.TechniqueCategory.matrixesRatios:
      return 'Culinary Matrixes & Ratios';
    case models.TechniqueCategory.knifeHeatManagement:
      return 'Knife Skills & Heat Management';
    case models.TechniqueCategory.europeanSubstitutes:
      return 'European Ingredient Substitutes';
    case models.TechniqueCategory.zeroWasteCrisperHacks:
      return 'Zero-Waste Crisper Hacks';
  }
}

String _durationLabelFromSeconds(int seconds) {
  final clamped = seconds < 0 ? 0 : seconds;
  final m = clamped ~/ 60;
  final s = clamped % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

TechniqueGradientSeed _gradientSeedForLesson(models.TechniqueLesson lesson) {
  final hash = lesson.id.hashCode.abs() % 3;
  return switch (hash) {
    0 => TechniqueGradientSeed.terracotta,
    1 => TechniqueGradientSeed.sage,
    _ => TechniqueGradientSeed.charcoal,
  };
}