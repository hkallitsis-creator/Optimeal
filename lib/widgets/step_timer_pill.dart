import 'package:flutter/material.dart';

import 'package:optimeal/theme/app_design_tokens.dart';

/// What the step timer is doing. **Idle is the default and the resting
/// state** — see [StepTimerPill].
enum StepTimerState {
  /// Showing the step's minutes, counting nothing. Every step starts here.
  idle,

  /// Counting down.
  running,

  /// Started, then stopped. The adjusters are still usable.
  paused,

  /// Reached zero. Beeped twice, buzzed once, and is now pulsing quietly
  /// until the user does something. **The step has not changed.**
  done,
}

/// The step timer, as a tappable pill.
///
/// # The ruling this implements, and what it replaced
///
/// The timer used to **start by itself** when a step opened and **advance the
/// step** when it ran out. Neither was ever in the signed Cook Mode spec —
/// there the timer is quiet text in the meta row, and promoting it at all is
/// evidence-gated. In practice it meant the app decided when you were done
/// cooking something, which is exactly backwards: the recipe's minutes are an
/// estimate, and the pan is the authority.
///
/// So: **nothing counts down until the user taps**, and **the step never
/// changes on its own, ever.** At zero the pill announces itself — two short
/// beeps, one haptic — and then pulses silently until the user acts. A cook
/// with wet hands who misses the beeps finds a pulsing pill, not a step they
/// have already been moved past.
///
/// The ± adjusters are live whenever the clock is not running, because the
/// minutes on the card are a guess and the cook can see the pan.
class StepTimerPill extends StatefulWidget {
  const StepTimerPill({
    super.key,
    required this.state,
    required this.remaining,
    required this.onTap,
    required this.onAdjust,
  });

  final StepTimerState state;

  /// Idle: the duration that will be counted. Running/paused: what is left.
  /// Done: zero.
  final Duration remaining;

  /// Idle → start · running → pause · paused → resume · done → stop pulsing
  /// (and stay on this step).
  final VoidCallback onTap;

  /// ±1 minute, floor 1. Null while running — the adjusters are hidden
  /// mid-countdown rather than disabled, because a greyed control mid-cook
  /// reads as broken.
  final ValueChanged<int>? onAdjust;

  @override
  State<StepTimerPill> createState() => _StepTimerPillState();
}

class _StepTimerPillState extends State<StepTimerPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(StepTimerPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncPulse();
  }

  void _syncPulse() {
    if (widget.state == StepTimerState.done) {
      // Slow, silent, and indefinite. The sound happens once; this is what
      // is still there thirty seconds later.
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  static String formatDuration(Duration d) {
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  String get _label => switch (widget.state) {
        // Idle shows whole minutes: a resting timer showing "07:00" invites
        // the reading that something is already counting.
        StepTimerState.idle => '${widget.remaining.inMinutes} min',
        StepTimerState.running => formatDuration(widget.remaining),
        // SIGNED-CONTENT PLACEHOLDER
        StepTimerState.paused => 'Paused · ${formatDuration(widget.remaining)}',
        // SIGNED-CONTENT PLACEHOLDER
        StepTimerState.done => 'Time',
      };

  IconData get _icon => switch (widget.state) {
        StepTimerState.idle => Icons.play_arrow_rounded,
        StepTimerState.running => Icons.pause_rounded,
        StepTimerState.paused => Icons.play_arrow_rounded,
        StepTimerState.done => Icons.check_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adjustable = widget.onAdjust != null &&
        widget.state != StepTimerState.running &&
        widget.state != StepTimerState.done;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final fill = widget.state == StepTimerState.done
            ? Color.lerp(AppDesignTokens.surfaceIvory,
                AppDesignTokens.champagneTint, _pulse.value)!
            : AppDesignTokens.neutralPillTint;

        return Material(
          color: fill,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (adjustable)
                    _AdjustGlyph(
                      icon: Icons.remove_rounded,
                      onTap: () => widget.onAdjust!(-1),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_icon,
                            size: 16,
                            color: AppDesignTokens.textCharcoal
                                .withValues(alpha: 0.70)),
                        const SizedBox(width: 5),
                        Text(
                          _label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppDesignTokens.textCharcoal
                                .withValues(alpha: 0.80),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (adjustable)
                    _AdjustGlyph(
                      icon: Icons.add_rounded,
                      onTap: () => widget.onAdjust!(1),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AdjustGlyph extends StatelessWidget {
  const _AdjustGlyph({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(icon, size: 17, color: AppDesignTokens.ctaTerracotta),
      ),
    );
  }
}
