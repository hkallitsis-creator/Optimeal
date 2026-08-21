import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:optimeal/theme/app_design_tokens.dart';

/// Which wait this card is covering.
///
/// The two stages behave differently because the two waits are different
/// lengths, and that is the whole reason this is one parameterized component
/// rather than two:
///
/// - [findingIdeas] is seconds. One static line. Cycling copy over a
///   two-second wait flickers — the user reads half a sentence and it changes.
/// - [writingRecipe] is 7–10s. The lines cycle, and they narrate **real
///   generation work**, which is what makes the wait feel like craft rather
///   than lag.
enum GenerationStage { findingIdeas, writingRecipe }

/// The one loading card, shown at every AI generation point.
///
/// **No progress bar, by signed decision.** Generation time is genuinely
/// unpredictable — it depends on the model, the prompt size and OpenAI's
/// current load — and a bar that stalls at 80% is worse than no bar, because
/// it makes a promise the app cannot keep. The pulsing dots say "alive" and
/// promise nothing.
///
/// **The cycling lines are claims about real behaviour, so they must stay
/// true.** Every line below describes something the pipeline actually does:
/// the ingredients go into the prompt, the static prompt carries a real
/// sequencing rule about staggering ingredients with different cook times,
/// every step is required to declare a `sensory_cue` from the signed
/// vocabulary, every ingredient declares a `cut`, and amounts are scaled to
/// the requested portions. **Do not add a line for work the pipeline does not
/// do** — there is no nutrition analysis, no cost calculation, and (roadmap
/// item 1) no safety validation, so none of those may be claimed here.
class GenerationLoadingCard extends StatefulWidget {
  const GenerationLoadingCard({
    super.key,
    required this.stage,
    this.subject,
    this.ingredients,
  });

  final GenerationStage stage;

  /// The dish being written, when there is one — shown quietly so the user
  /// keeps hold of what they chose while they wait for it.
  final String? subject;

  /// The user's own ingredients, when the calling surface has them. Used to
  /// make one cycling line concrete ("Using your zucchini and eggs…") rather
  /// than generic. Optional: the Custom recipe creator takes free text and has
  /// no structured list to pass, and static lines are the floor.
  final List<String>? ingredients;

  /// Lines for the short wait. One static line, no cycling.
  // PLACEHOLDER (both)
  static const String findingIdeasLine = 'Looking at what you\'ve got…';
  // PLACEHOLDER
  static const String findingIdeasSubLine =
      'Chef Harris is working out a few ways to use it up.';

  /// Lines for the long wait. Each names real work — see the class doc.
  // PLACEHOLDER (all)
  static const List<String> writingRecipeLines = [
    'Reading your ingredients…',
    'Setting the pan order — what goes in first, and when the rest joins…',
    'Working out how to cut each thing…',
    'Adding what to look and listen for at every step…',
    'Scaling the amounts to your portions…',
  ];

  // PLACEHOLDER
  static const String writingRecipeSubLine =
      'This is the slow part. Worth it.';

  /// How long each line holds before the next.
  static const Duration lineInterval = Duration(milliseconds: 2500);

  @override
  State<GenerationLoadingCard> createState() => _GenerationLoadingCardState();
}

class _GenerationLoadingCardState extends State<GenerationLoadingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _lineIndex = 0;

  /// The cycling lines for this instance, with the ingredient-aware line
  /// substituted in when the caller gave us something to name.
  late final List<String> _lines = _buildLines();

  List<String> _buildLines() {
    final lines = List<String>.from(GenerationLoadingCard.writingRecipeLines);
    final ingredients = widget.ingredients
            ?.map((e) => e.trim().toLowerCase())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    if (ingredients.length >= 2) {
      // Truthful: those ingredients really are in the prompt for this call.
      // PLACEHOLDER
      lines[0] =
          'Reading your ${ingredients[0]} and ${ingredients[1]}…';
    }
    return lines;
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      // Calm. The spoon should look like someone stirring while they think,
      // not like a spinner pretending to be a spoon.
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    if (widget.stage == GenerationStage.writingRecipe) {
      _controller.addListener(_advanceLineOnInterval);
    }
  }

  /// Advances the copy off the animation clock rather than a second `Timer`,
  /// so a paused/disabled animation cannot leave a stale line cycling behind
  /// a frozen illustration.
  Duration _lastLineChange = Duration.zero;
  void _advanceLineOnInterval() {
    final elapsed = _controller.lastElapsedDuration;
    if (elapsed == null) return;
    if (elapsed - _lastLineChange < GenerationLoadingCard.lineInterval) return;
    _lastLineChange = elapsed;
    if (!mounted) return;
    setState(() => _lineIndex = (_lineIndex + 1) % _lines.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduced motion: a still illustration and still dots. The card still
    // says "something is happening" through its copy; nothing moves.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion && _controller.isAnimating) {
      _controller.stop();
    } else if (!reduceMotion && !_controller.isAnimating) {
      _controller.repeat();
    }

    final isWriting = widget.stage == GenerationStage.writingRecipe;
    final line =
        isWriting ? _lines[_lineIndex] : GenerationLoadingCard.findingIdeasLine;
    final subLine = isWriting
        ? GenerationLoadingCard.writingRecipeSubLine
        : GenerationLoadingCard.findingIdeasSubLine;

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppDesignTokens.spaceMD),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              decoration: BoxDecoration(
                color: AppDesignTokens.surfaceIvory,
                borderRadius:
                    BorderRadius.circular(AppDesignTokens.radiusCard),
                border: Border.all(
                    color:
                        AppDesignTokens.textCharcoal.withValues(alpha: 0.10)),
                boxShadow: AppDesignTokens.cardShadow,
              ),
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => SizedBox(
                      height: 132,
                      width: 176,
                      child: CustomPaint(
                        painter: _StirringSpoonPainter(
                          // A fixed phase when motion is reduced, so the
                          // illustration is composed rather than frozen
                          // mid-swing.
                          t: reduceMotion ? 0.12 : _controller.value,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDesignTokens.spaceMD),
                  if (widget.subject != null) ...[
                    Text(
                      widget.subject!,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppDesignTokens.subheadline.copyWith(height: 1.2),
                    ),
                    const SizedBox(height: 10),
                  ],
                  // The line swaps with a cross-fade; a hard cut reads as a
                  // glitch at this size.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    child: Text(
                      line,
                      key: ValueKey(line),
                      textAlign: TextAlign.center,
                      style: AppDesignTokens.body.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                        color: AppDesignTokens.textCharcoal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subLine,
                    textAlign: TextAlign.center,
                    style: AppDesignTokens.caption.copyWith(height: 1.35),
                  ),
                  const SizedBox(height: AppDesignTokens.spaceMD),
                  _PulsingDots(
                      controller: _controller, animate: !reduceMotion),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three dots that breathe. Says "alive", promises nothing — which is the
/// whole reason there is no progress bar above them.
class _PulsingDots extends StatelessWidget {
  const _PulsingDots({required this.controller, required this.animate});

  final AnimationController controller;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            // Staggered, so they read as a wave rather than a blink.
            final phase = (controller.value + i * 0.18) % 1.0;
            final swell =
                animate ? (0.55 + 0.45 * math.sin(phase * 2 * math.pi)) : 0.7;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 7,
              width: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppDesignTokens.ctaTerracotta
                    .withValues(alpha: swell.clamp(0.18, 1.0)),
              ),
            );
          }),
        );
      },
    );
  }
}

/// A wooden spoon stirring a terracotta bowl.
///
/// Signed diagram-family rules: black perimeter outline on every shape, flat
/// fills, no gradients. The spoon **dips behind the far rim** — done purely
/// with paint order, drawing the spoon before the batter surface while it is
/// on the far half of its swing and after it while it is near.
class _StirringSpoonPainter extends CustomPainter {
  const _StirringSpoonPainter({required this.t});

  /// 0..1 animation phase.
  final double t;

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
    final batterFill = Paint()
      ..color = AppDesignTokens.champagneTint
      ..style = PaintingStyle.fill;
    final shadowFill = Paint()
      ..color = AppDesignTokens.sageTeachingPanel
      ..style = PaintingStyle.fill;
    final woodFill = Paint()
      ..color = AppDesignTokens.illustrationWoodTan
      ..style = PaintingStyle.fill;
    final woodShade = Paint()
      ..color = AppDesignTokens.illustrationWoodTanShade
      ..style = PaintingStyle.fill;

    // Geometry.
    final cx = size.width * 0.5;
    final rimY = size.height * 0.52;
    final rimRx = size.width * 0.30;
    final rimRy = size.height * 0.09;
    final bowlDepth = size.height * 0.30;

    // ── Base shadow (sage), sitting under the bowl. ──
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, rimY + bowlDepth + size.height * 0.06),
          width: rimRx * 2.05,
          height: size.height * 0.10),
      shadowFill,
    );

    // ── Bowl body: rim ellipse down to a rounded base. ──
    final bowl = Path()
      ..moveTo(cx - rimRx, rimY)
      ..quadraticBezierTo(
          cx - rimRx * 0.96, rimY + bowlDepth * 1.28, cx, rimY + bowlDepth)
      ..quadraticBezierTo(
          cx + rimRx * 0.96, rimY + bowlDepth * 1.28, cx + rimRx, rimY)
      ..close();
    canvas.drawPath(bowl, bowlFill);

    // The swing: a smooth there-and-back, not a full spin — a person stirring.
    final angle = math.sin(t * 2 * math.pi) * 2.4;
    final headX = cx + math.cos(angle) * rimRx * 0.52;
    final headY = rimY + math.sin(angle) * rimRy * 0.85;
    // Far half of the swing: the head is behind the batter surface.
    final isBehind = math.sin(angle) < 0;

    void drawSpoon() {
      canvas.save();
      canvas.translate(headX, headY);
      // Handle leans away from centre, so the spoon reads as held.
      canvas.rotate(-0.5 + math.cos(angle) * 0.28);

      final handle = Rect.fromLTWH(-size.width * 0.017, -size.height * 0.46,
          size.width * 0.034, size.height * 0.46);
      canvas.drawRRect(
          RRect.fromRectAndRadius(handle, const Radius.circular(5)), woodFill);
      canvas.drawRRect(
          RRect.fromRectAndRadius(handle, const Radius.circular(5)), line);

      final head = Rect.fromCenter(
          center: Offset.zero,
          width: size.width * 0.085,
          height: size.height * 0.13);
      canvas.drawOval(head, woodFill);
      // Shading crescent — the only modelling on the whole illustration.
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(head.width * 0.14, head.height * 0.10),
              width: head.width * 0.62,
              height: head.height * 0.62),
          woodShade);
      canvas.drawOval(head, line);
      canvas.restore();
    }

    if (isBehind) drawSpoon();

    // ── Batter surface, drawn over a behind-the-rim spoon. ──
    final rim = Rect.fromCenter(
        center: Offset(cx, rimY), width: rimRx * 2, height: rimRy * 2);
    canvas.drawOval(rim, batterFill);

    // Three pearls riding the surface with the spoon.
    for (var i = 0; i < 3; i++) {
      final pearlAngle = angle + 1.5 + i * 1.9;
      final px = cx + math.cos(pearlAngle) * rimRx * 0.62;
      final py = rimY + math.sin(pearlAngle) * rimRy * 0.62;
      final r = size.width * (0.0125 + (i == 1 ? 0.004 : 0));
      // Two terracotta, one gold. The gold pearl is the ONE place gold appears
      // outside an earned moment — signed explicitly by this card's spec, and
      // at 2px it reads as a highlight rather than a badge. Flagged in the
      // session record.
      final fill = Paint()
        ..color = i == 1
            ? AppDesignTokens.goldEarnedFill
            : AppDesignTokens.ctaTerracotta
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(px, py), r, fill);
      canvas.drawCircle(
          Offset(px, py),
          r,
          Paint()
            ..color = AppDesignTokens.textCharcoal
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
    }

    if (!isBehind) drawSpoon();

    // ── Outlines last, so nothing paints over the perimeter. ──
    canvas.drawPath(bowl, line);
    canvas.drawOval(rim, line);
  }

  @override
  bool shouldRepaint(_StirringSpoonPainter oldDelegate) =>
      oldDelegate.t != t;
}
