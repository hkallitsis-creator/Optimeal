import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:optimeal/theme/app_design_tokens.dart';

/// The wooden spoon stirring a terracotta bowl — **one** illustration, shared
/// by the generation loading card (animated) and onboarding slide 1 (static).
///
/// It was drawn twice before this, and the two copies drifted: on a Pixel,
/// onboarding slide 1 rendered as a detached terracotta dome with a floating
/// spoon beside it, reading as a hat and a lollipop. One painter, one source
/// of truth.
///
/// # Diagram-style rules, per the signed spec
///
/// Black perimeter outlines on every shape; terracotta bowl with a champagne
/// batter surface; sage elliptical base shadow. The spoon is wood tan, which
/// is deliberately **outside** the semantic palette — it is an illustration
/// colour and must never be readable as gold/earned. Those two tokens live in
/// the marked ILLUSTRATION-ONLY section of `AppDesignTokens`.
///
/// One of the three batter pearls is gold. That is signed by name: at ~2px it
/// reads as a highlight, not a badge.
class SpoonBowlIllustration extends StatelessWidget {
  const SpoonBowlIllustration({
    super.key,
    required this.phase,
    this.width = 176,
    this.height = 132,
  });

  /// The pose that onboarding and reduced-motion both freeze at. Mid-stir and
  /// off-centre, so the illustration reads as composed rather than stopped.
  static const double staticPhase = 0.12;

  /// 0..1 animation phase.
  final double phase;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: SpoonBowlPainter(t: phase)),
    );
  }
}

/// Where every part of the illustration sits, as pure arithmetic.
///
/// Split out of the painter so the containment rule can be *tested* rather
/// than eyeballed: the paddle leaving the bowl is a geometry bug, and a
/// geometry bug is checkable without rendering anything.
@immutable
class SpoonBowlGeometry {
  const SpoonBowlGeometry(this.size);

  final Size size;

  double get cx => size.width * 0.5;
  double get rimY => size.height * 0.52;
  double get rimRx => size.width * 0.30;

  /// Deeper than it looks necessary, and that is the point: the paddle has to
  /// fit *inside* this ellipse at every phase, and the old value (0.09) was
  /// shallower than the paddle was tall.
  double get rimRy => size.height * 0.13;

  double get bowlDepth => size.height * 0.30;

  double get paddleWidth => size.width * 0.07;
  double get paddleHeight => size.height * 0.085;

  /// A circular bound on the paddle. The paddle is an ellipse that also
  /// **rotates**, so its true extent along any axis varies with the phase;
  /// bounding it by a circle of its longest half-axis makes containment a
  /// single comparison that no rotation can defeat.
  double get paddleRadius => math.max(paddleWidth, paddleHeight) / 2;

  /// How far the orbit is scaled in from the rim, as a fraction.
  ///
  /// **Insetting each axis by the paddle radius independently does not work**,
  /// and that was the original bug's real shape: it leaves the paddle outside
  /// the ellipse on the diagonals even though it fits on both axes. Writing
  /// the containment condition out gives a closed form instead.
  ///
  /// With the orbit as the rim scaled by `k`, and `u`,`v` the paddle radius in
  /// units of each rim semi-axis, the worst case over all angles is
  /// `(k + hypot(u, v))² ≤ 1` — so `k ≤ 1 - hypot(u, v)`. The 0.95 keeps the
  /// outline off the rim stroke.
  double get _orbitScale {
    final u = paddleRadius / rimRx;
    final v = paddleRadius / rimRy;
    return math.max(0, (1 - math.sqrt(u * u + v * v)) * 0.95);
  }

  /// The orbit is derived from the rim, never chosen independently — this is
  /// the clamp. Containment therefore holds by construction at every phase and
  /// every size, rather than for the phases someone happened to check.
  double get orbitRx => rimRx * _orbitScale;
  double get orbitRy => rimRy * _orbitScale;

  /// A there-and-back swing, not a full spin — a person stirring.
  double angleAt(double t) => math.sin(t * 2 * math.pi) * 2.4;

  Offset paddleCenterAt(double t) {
    final a = angleAt(t);
    return Offset(cx + math.cos(a) * orbitRx, rimY + math.sin(a) * orbitRy);
  }

  /// True while the paddle is on the far side, i.e. behind the batter.
  bool isBehindAt(double t) => math.sin(angleAt(t)) < 0;

  /// The containment invariant: the paddle, bounded by its circle, lies
  /// entirely within the rim ellipse.
  bool paddleInsideRim(double t) {
    final c = paddleCenterAt(t);
    final dx = (c.dx - cx).abs() + paddleRadius;
    final dy = (c.dy - rimY).abs() + paddleRadius;
    final norm = (dx / rimRx) * (dx / rimRx) + (dy / rimRy) * (dy / rimRy);
    return norm <= 1.0 + 1e-9;
  }
}

class SpoonBowlPainter extends CustomPainter {
  const SpoonBowlPainter({required this.t});

  /// 0..1 animation phase.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final g = SpoonBowlGeometry(size);

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

    // ── Sage base shadow ────────────────────────────────────────────────────
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(g.cx, g.rimY + g.bowlDepth + size.height * 0.06),
        width: g.rimRx * 2.05,
        height: size.height * 0.10,
      ),
      shadowFill,
    );

    // ── Bowl body ───────────────────────────────────────────────────────────
    // ONE cubic, not two quadratics meeting at the base. The old path joined
    // two curves whose tangents pointed in opposite vertical directions, which
    // is a cusp — and a cusp is exactly the notch that showed up at the bottom
    // of the bowl on device. A single cubic has no join to go wrong.
    final bowlBody = Path()
      ..moveTo(g.cx - g.rimRx, g.rimY)
      ..cubicTo(
        g.cx - g.rimRx * 0.98, g.rimY + g.bowlDepth * 1.55,
        g.cx + g.rimRx * 0.98, g.rimY + g.bowlDepth * 1.55,
        g.cx + g.rimRx, g.rimY,
      );

    final bowlFilled = Path.from(bowlBody)..close();
    canvas.drawPath(bowlFilled, bowlFill);

    // ── Batter surface ──────────────────────────────────────────────────────
    final rim = Rect.fromCenter(
      center: Offset(g.cx, g.rimY),
      width: g.rimRx * 2,
      height: g.rimRy * 2,
    );
    canvas.drawOval(rim, batterFill);

    // Far rim first: the top arc, drawn before the spoon so the spoon reads as
    // being inside the bowl rather than sitting on a flat disc.
    canvas.drawArc(rim, math.pi, math.pi, false, line);

    // ── Pearls, riding the surface with the spoon ───────────────────────────
    final a = g.angleAt(t);
    for (var i = 0; i < 3; i++) {
      final pearlAngle = a + 1.5 + i * 1.9;
      final px = g.cx + math.cos(pearlAngle) * g.orbitRx * 0.72;
      final py = g.rimY + math.sin(pearlAngle) * g.orbitRy * 0.72;
      final r = size.width * (0.0125 + (i == 1 ? 0.004 : 0));
      // Two terracotta, one gold — signed by name for this illustration.
      canvas.drawCircle(
        Offset(px, py),
        r,
        Paint()
          ..color = i == 1
              ? AppDesignTokens.goldEarnedFill
              : AppDesignTokens.ctaTerracotta
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(px, py),
        r,
        Paint()
          ..color = AppDesignTokens.textCharcoal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    // ── Spoon ───────────────────────────────────────────────────────────────
    final centre = g.paddleCenterAt(t);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(-0.5 + math.cos(a) * 0.28);

    final handle = Rect.fromLTWH(
      -size.width * 0.017,
      -size.height * 0.46,
      size.width * 0.034,
      size.height * 0.46,
    );
    canvas.drawRRect(
        RRect.fromRectAndRadius(handle, const Radius.circular(5)), woodFill);
    canvas.drawRRect(
        RRect.fromRectAndRadius(handle, const Radius.circular(5)), line);

    final paddle = Rect.fromCenter(
      center: Offset.zero,
      width: g.paddleWidth,
      height: g.paddleHeight,
    );
    canvas.drawOval(paddle, woodFill);
    // Shading crescent — the only modelling on the whole illustration.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(paddle.width * 0.14, paddle.height * 0.10),
        width: paddle.width * 0.62,
        height: paddle.height * 0.62,
      ),
      woodShade,
    );
    canvas.drawOval(paddle, line);
    canvas.restore();

    // ── Near rim last, so the spoon dips behind it ──────────────────────────
    canvas.drawArc(rim, 0, math.pi, false, line);

    // Bowl perimeter last of all — nothing paints over an outline.
    canvas.drawPath(bowlBody, line);
  }

  @override
  bool shouldRepaint(SpoonBowlPainter oldDelegate) => oldDelegate.t != t;
}
