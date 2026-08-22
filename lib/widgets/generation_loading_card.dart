import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/spoon_bowl_illustration.dart';

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
                    builder: (context, _) => SpoonBowlIllustration(
                      // A fixed phase when motion is reduced, so the
                      // illustration is composed rather than frozen mid-swing.
                      phase: reduceMotion
                          ? SpoonBowlIllustration.staticPhase
                          : _controller.value,
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
