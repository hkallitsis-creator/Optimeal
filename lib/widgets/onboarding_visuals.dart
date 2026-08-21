import 'package:flutter/material.dart';

import 'package:optimeal/theme/app_design_tokens.dart';

/// The four small in-slide visuals for onboarding.
///
/// Two of them are **previews of real UI** (the cue panel, the week strip) and
/// are deliberately simplified static copies rather than the live widgets:
/// the real ones carry state, gestures and service dependencies that a slide
/// has no business owning, and a preview that responds to taps would promise
/// an interaction the slide cannot deliver. They reuse the real *tokens*, so
/// the colours a user learns here are the colours they will meet.
///
/// The other two are line illustrations in the signed diagram family — see
/// `technique_diagrams.dart`: flat, black outlines ([AppDesignTokens.textCharcoal]),
/// terracotta fills, no gradients, no photos, no AI imagery.

/// Slide 1 — spoon and bowl.
class SpoonAndBowlIllustration extends StatelessWidget {
  const SpoonAndBowlIllustration({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: size,
        width: size * 1.4,
        child: const CustomPaint(painter: _SpoonAndBowlPainter()),
      );
}

class _SpoonAndBowlPainter extends CustomPainter {
  const _SpoonAndBowlPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = AppDesignTokens.textCharcoal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final bowlFill = Paint()
      ..color = AppDesignTokens.ctaTerracotta
      ..style = PaintingStyle.fill;
    // "Wood-tan" has no signed token; champagne is the palette's warm neutral
    // and is already the terracotta family's background wash, so it reads as
    // wood beside a terracotta bowl without spending another semantic.
    final spoonFill = Paint()
      ..color = AppDesignTokens.champagneTint
      ..style = PaintingStyle.fill;

    // ── Bowl: a rounded half-ellipse sitting on a small foot. ──
    final bowlRect = Rect.fromLTWH(
        size.width * 0.06, size.height * 0.34, size.width * 0.52, size.height * 0.46);
    final bowl = Path()
      ..moveTo(bowlRect.left, bowlRect.top)
      ..lineTo(bowlRect.right, bowlRect.top)
      ..arcToPoint(
        Offset(bowlRect.left, bowlRect.top),
        radius: Radius.elliptical(bowlRect.width * 0.5, bowlRect.height),
        clockwise: false,
      )
      ..close();
    canvas.drawPath(bowl, bowlFill);
    canvas.drawPath(bowl, line);

    // Rim, drawn over the fill so the bowl reads as open rather than solid.
    canvas.drawLine(Offset(bowlRect.left - 3, bowlRect.top),
        Offset(bowlRect.right + 3, bowlRect.top), line);

    // Foot.
    final footY = bowlRect.bottom + size.height * 0.06;
    canvas.drawLine(Offset(bowlRect.center.dx - bowlRect.width * 0.16, footY),
        Offset(bowlRect.center.dx + bowlRect.width * 0.16, footY), line);

    // Steam — three short strokes above the rim, the only "it's cooking" cue.
    for (var i = 0; i < 3; i++) {
      final x = bowlRect.left + bowlRect.width * (0.28 + i * 0.22);
      final top = bowlRect.top - size.height * (0.24 - i % 2 * 0.06);
      canvas.drawLine(
          Offset(x, bowlRect.top - size.height * 0.08), Offset(x, top), line);
    }

    // ── Spoon: an elliptical head with a straight handle, angled behind. ──
    canvas.save();
    canvas.translate(size.width * 0.74, size.height * 0.52);
    canvas.rotate(-0.42);

    final head = Rect.fromCenter(
        center: Offset.zero, width: size.width * 0.17, height: size.height * 0.30);
    canvas.drawOval(head, spoonFill);
    canvas.drawOval(head, line);

    final handle = Rect.fromLTWH(-size.width * 0.028, head.bottom - 2,
        size.width * 0.056, size.height * 0.42);
    canvas.drawRRect(
        RRect.fromRectAndRadius(handle, const Radius.circular(6)), spoonFill);
    canvas.drawRRect(
        RRect.fromRectAndRadius(handle, const Radius.circular(6)), line);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpoonAndBowlPainter oldDelegate) => false;
}

/// Slide 2 — fridge glyph, same diagram family.
class FridgeIllustration extends StatelessWidget {
  const FridgeIllustration({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: size,
        width: size * 1.4,
        child: const CustomPaint(painter: _FridgePainter()),
      );
}

class _FridgePainter extends CustomPainter {
  const _FridgePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = AppDesignTokens.textCharcoal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final doorFill = Paint()
      ..color = AppDesignTokens.ctaTerracotta.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    final produceFill = Paint()
      ..color = AppDesignTokens.ctaTerracotta
      ..style = PaintingStyle.fill;

    final body = Rect.fromLTWH(size.width * 0.30, size.height * 0.08,
        size.width * 0.40, size.height * 0.84);
    final rrect =
        RRect.fromRectAndRadius(body, const Radius.circular(8));
    canvas.drawRRect(rrect, doorFill);
    canvas.drawRRect(rrect, line);

    // The freezer/fridge split.
    final splitY = body.top + body.height * 0.32;
    canvas.drawLine(Offset(body.left, splitY), Offset(body.right, splitY), line);

    // Handles — two short verticals just right of the split line.
    final handleX = body.left + body.width * 0.16;
    canvas.drawLine(Offset(handleX, splitY - body.height * 0.16),
        Offset(handleX, splitY - body.height * 0.06), line);
    canvas.drawLine(Offset(handleX, splitY + body.height * 0.08),
        Offset(handleX, splitY + body.height * 0.22), line);

    // Something worth rescuing inside, showing through the open lower door.
    final produce = Offset(body.center.dx + body.width * 0.14,
        splitY + body.height * 0.30);
    canvas.drawCircle(produce, size.width * 0.045, produceFill);
    canvas.drawCircle(produce, size.width * 0.045, line);
    canvas.drawLine(produce + Offset(0, -size.width * 0.045),
        produce + Offset(size.width * 0.03, -size.width * 0.085), line);
  }

  @override
  bool shouldRepaint(_FridgePainter oldDelegate) => false;
}

/// Slide 3 — a miniature of Cook Mode's cue panel.
///
/// The point is pre-teaching the colour: by the time a user meets a sage panel
/// mid-cook, they should already read green as "Chef Harris is teaching me",
/// not as decoration. Same [AppDesignTokens.sageTeachingPanel] fill and the
/// same small-caps label shape as the real `_CuePanel`.
class MiniCuePanelPreview extends StatelessWidget {
  const MiniCuePanelPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppDesignTokens.sageTeachingPanel,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            // PLACEHOLDER
            'HOW YOU KNOW IT\'S RIGHT',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
              color: AppDesignTokens.deepForest,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            // PLACEHOLDER
            'Tilt the pan. When the oil runs thin and shimmers, it is ready.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: AppDesignTokens.textCharcoal,
            ),
          ),
        ],
      ),
    );
  }
}

/// Slide 4 — a miniature week strip previewing the three day states a user
/// will actually meet in the Weekly Planner: cooked-and-counted, today, and
/// empty.
///
/// Static by design. A preview that responded to taps would promise a planner
/// that does not exist yet on this screen.
class MiniWeekStripPreview extends StatelessWidget {
  const MiniWeekStripPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MiniDayRow(day: 'MON', state: _MiniDayState.cookedCounted),
        SizedBox(height: 6),
        _MiniDayRow(day: 'TUE', state: _MiniDayState.today),
        SizedBox(height: 6),
        _MiniDayRow(day: 'WED', state: _MiniDayState.empty),
      ],
    );
  }
}

enum _MiniDayState { cookedCounted, today, empty }

class _MiniDayRow extends StatelessWidget {
  const _MiniDayRow({required this.day, required this.state});

  final String day;
  final _MiniDayState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToday = state == _MiniDayState.today;
    final isEmpty = state == _MiniDayState.empty;

    final label = Text(
      day,
      style: theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
        color: isToday
            ? AppDesignTokens.terracottaOnLight
            : AppDesignTokens.textCharcoal.withValues(alpha: 0.55),
      ),
    );

    final body = switch (state) {
      _MiniDayState.cookedCounted => Row(
          children: [
            Expanded(
              child: Text(
                // PLACEHOLDER
                'Zucchini Frittata',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        AppDesignTokens.textCharcoal.withValues(alpha: 0.58)),
              ),
            ),
            const Icon(Icons.check_circle_rounded,
                size: 16, color: AppDesignTokens.goldEarnedOnLight),
          ],
        ),
      _MiniDayState.today => Row(
          children: [
            Expanded(
              child: Text(
                // PLACEHOLDER
                'Potato Hash',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppDesignTokens.textCharcoal),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppDesignTokens.ctaTerracotta,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                // PLACEHOLDER
                'Cook',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      _MiniDayState.empty => Row(
          children: [
            Expanded(
              child: Text(
                // PLACEHOLDER
                'Nothing planned',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: AppDesignTokens.deepForest.withValues(alpha: 0.62)),
              ),
            ),
            Text('+',
                style: theme.textTheme.titleMedium?.copyWith(
                    color: AppDesignTokens.terracottaOnLight,
                    fontWeight: FontWeight.w900,
                    height: 1)),
          ],
        ),
    };

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 34, child: label),
          Expanded(child: body),
        ],
      ),
    );

    // The empty day is a dashed outline on the canvas, exactly as the planner
    // draws it; the other two are filled cards.
    if (isEmpty) {
      return CustomPaint(
        painter: _MiniDashedBorderPainter(),
        child: row,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isToday
            ? AppDesignTokens.champagneTint
            : AppDesignTokens.quietRowSurface,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip),
        border: Border.all(
          color: isToday
              ? AppDesignTokens.ctaTerracotta.withValues(alpha: 0.30)
              : AppDesignTokens.textCharcoal.withValues(alpha: 0.10),
        ),
      ),
      child: row,
    );
  }
}

/// Miniature of the planner's dashed empty-day outline.
class _MiniDashedBorderPainter extends CustomPainter {
  static const double _dash = 5;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppDesignTokens.deepForest.withValues(alpha: 0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size,
          const Radius.circular(AppDesignTokens.radiusChip)));

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_MiniDashedBorderPainter oldDelegate) => false;
}
