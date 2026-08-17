import 'package:flutter/material.dart';

import 'package:optimeal/theme/app_design_tokens.dart';

/// Three pilot deterministic diagrams — docs/decisions_2026-08-17.md item 4:
/// instructional line drawings, flat, two colors from [AppDesignTokens]
/// (deepForest = "right"/correct, ctaTerracotta = "wrong"/caution) plus
/// [AppDesignTokens.textCharcoal] as the line color. No gradients, no
/// decoration, no AI-generated images, no photos.
///
/// Implemented as [CustomPainter] vector drawings rather than literal
/// `.svg` asset files + a new `flutter_svg` package dependency — same
/// deterministic/flat/two-color-plus-line spec, avoids adding an external
/// dependency this late with no device available to verify pub resolution
/// on. See lib/widgets/diagram_sheet.dart for how these are looked up by
/// key and shown.

const double _kLineWidth = 2.2;
const double _kLabelFontSize = 11;

TextPainter _label(String text, Color color, {FontWeight weight = FontWeight.w700}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: _kLabelFontSize, fontWeight: weight),
    ),
    textDirection: TextDirection.ltr,
  );
  painter.layout();
  return painter;
}

/// Cut reference diagram for the "julienne" cut vocabulary value. A single
/// panel: the food piece, the cut direction, and the resulting strips with
/// their dimensions labelled. Deliberately no hands or knife grip drawn —
/// hand positions are teaching content Harris specifies himself, if ever
/// included.
class JulienneCutPainter extends CustomPainter {
  const JulienneCutPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = AppDesignTokens.textCharcoal
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kLineWidth
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = AppDesignTokens.deepForest.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;

    // Left: the whole piece before cutting.
    final block = Rect.fromLTWH(size.width * 0.06, size.height * 0.30, size.width * 0.22, size.height * 0.40);
    canvas.drawRRect(RRect.fromRectAndRadius(block, const Radius.circular(4)), fill);
    canvas.drawRRect(RRect.fromRectAndRadius(block, const Radius.circular(4)), line);

    // Arrow from the block toward the strips, showing the cut direction.
    final arrowY = size.height * 0.50;
    final arrowStart = Offset(block.right + 10, arrowY);
    final arrowEnd = Offset(size.width * 0.42, arrowY);
    canvas.drawLine(arrowStart, arrowEnd, line);
    final arrowHead = Path()
      ..moveTo(arrowEnd.dx, arrowEnd.dy)
      ..lineTo(arrowEnd.dx - 8, arrowEnd.dy - 5)
      ..lineTo(arrowEnd.dx - 8, arrowEnd.dy + 5)
      ..close();
    canvas.drawPath(arrowHead, Paint()..color = AppDesignTokens.textCharcoal);

    // Right: the resulting julienne strips — thin, long, parallel.
    const stripCount = 5;
    final stripsLeft = size.width * 0.48;
    final stripsWidth = size.width * 0.42;
    final stripsTop = size.height * 0.22;
    final stripsHeight = size.height * 0.56;
    final stripGap = stripsWidth / (stripCount * 2 - 1);
    for (var i = 0; i < stripCount; i++) {
      final left = stripsLeft + i * stripGap * 2;
      final strip = Rect.fromLTWH(left, stripsTop, stripGap, stripsHeight);
      canvas.drawRRect(RRect.fromRectAndRadius(strip, const Radius.circular(2)), fill);
      canvas.drawRRect(RRect.fromRectAndRadius(strip, const Radius.circular(2)), line);
    }

    // Dimension labels: strip width and strip length, on the last strip.
    final lastStripLeft = stripsLeft + (stripCount - 1) * stripGap * 2;
    final widthLabel = _label('≈3mm', AppDesignTokens.textCharcoal);
    widthLabel.paint(canvas, Offset(lastStripLeft - widthLabel.width / 2 + stripGap / 2, stripsTop - 16));

    final lengthLabel = _label('≈5cm', AppDesignTokens.textCharcoal);
    canvas.save();
    canvas.translate(stripsLeft + stripsWidth + 6, stripsTop + stripsHeight / 2 + lengthLabel.width / 2);
    canvas.rotate(-1.5708); // -90deg
    lengthLabel.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Shared scaffold for the two "wrong vs. right" two-panel technique
/// diagrams (pan_crowding, cold_vs_hot_pan) — a vertical divider, a
/// terracotta-labelled left panel, a deepForest-labelled right panel.
class _TwoPanelPainter extends CustomPainter {
  const _TwoPanelPainter({
    required this.wrongLabel,
    required this.rightLabel,
    required this.drawWrong,
    required this.drawRight,
  });

  final String wrongLabel;
  final String rightLabel;
  final void Function(Canvas canvas, Rect panel) drawWrong;
  final void Function(Canvas canvas, Rect panel) drawRight;

  @override
  void paint(Canvas canvas, Size size) {
    final divider = Paint()
      ..color = AppDesignTokens.textCharcoal.withValues(alpha: 0.20)
      ..strokeWidth = 1;
    final midX = size.width / 2;
    canvas.drawLine(Offset(midX, size.height * 0.08), Offset(midX, size.height * 0.92), divider);

    final leftPanel = Rect.fromLTWH(0, size.height * 0.14, midX - 8, size.height * 0.72);
    final rightPanel = Rect.fromLTWH(midX + 8, size.height * 0.14, midX - 8, size.height * 0.72);

    drawWrong(canvas, leftPanel);
    drawRight(canvas, rightPanel);

    final wrong = _label(wrongLabel.toUpperCase(), AppDesignTokens.ctaTerracotta, weight: FontWeight.w900);
    wrong.paint(canvas, Offset(leftPanel.center.dx - wrong.width / 2, 0));
    final right = _label(rightLabel.toUpperCase(), AppDesignTokens.deepForest, weight: FontWeight.w900);
    right.paint(canvas, Offset(rightPanel.center.dx - right.width / 2, 0));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void _panWithPieces(Canvas canvas, Rect panel, Color accent, List<Offset> centers, double radius) {
  final panRadius = panel.width * 0.42;
  final panCenter = Offset(panel.center.dx, panel.center.dy + 6);
  final panLine = Paint()
    ..color = AppDesignTokens.textCharcoal
    ..style = PaintingStyle.stroke
    ..strokeWidth = _kLineWidth;
  canvas.drawCircle(panCenter, panRadius, panLine);

  final pieceFill = Paint()..color = accent.withValues(alpha: 0.22);
  final pieceLine = Paint()
    ..color = accent
    ..style = PaintingStyle.stroke
    ..strokeWidth = _kLineWidth;
  for (final c in centers) {
    final pos = panCenter + c;
    canvas.drawCircle(pos, radius, pieceFill);
    canvas.drawCircle(pos, radius, pieceLine);
  }
}

/// Technique diagram for "pan_crowding" — too much food in the pan at
/// once (steams instead of browns) vs. properly spaced pieces.
class PanCrowdingPainter extends CustomPainter {
  const PanCrowdingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scaffold = _TwoPanelPainter(
      wrongLabel: 'Crowded',
      rightLabel: 'Spaced out',
      drawWrong: (canvas, panel) {
        final r = panel.width * 0.085;
        final centers = <Offset>[];
        for (var row = -1; row <= 1; row++) {
          for (var col = -1; col <= 1; col++) {
            centers.add(Offset(col * r * 1.7, row * r * 1.7));
          }
        }
        _panWithPieces(canvas, panel, AppDesignTokens.ctaTerracotta, centers, r);
      },
      drawRight: (canvas, panel) {
        final r = panel.width * 0.09;
        final centers = <Offset>[
          Offset(-r * 3.0, -r * 2.2),
          Offset(r * 3.0, -r * 2.2),
          const Offset(0, 0),
          Offset(-r * 3.0, r * 2.2),
          Offset(r * 3.0, r * 2.2),
        ];
        _panWithPieces(canvas, panel, AppDesignTokens.deepForest, centers, r);
      },
    );
    scaffold.paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void _heatLines(Canvas canvas, Offset panCenter, double panRadius, Color color, {required bool hot}) {
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..strokeCap = StrokeCap.round;
  if (!hot) {
    // Cold pan: a single flat dashed line under the food, no rising lines.
    final y = panCenter.dy + panRadius * 0.55;
    for (var x = panCenter.dx - panRadius * 0.5; x < panCenter.dx + panRadius * 0.5; x += 10) {
      canvas.drawLine(Offset(x, y), Offset(x + 5, y), paint);
    }
    return;
  }
  // Hot pan: small wavy rising lines around the food (sizzle/steam).
  for (final dx in [-panRadius * 0.35, 0.0, panRadius * 0.35]) {
    final path = Path()..moveTo(panCenter.dx + dx, panCenter.dy - panRadius * 0.15);
    path.relativeCubicTo(-6, -8, 6, -14, 0, -22);
    canvas.drawPath(path, paint);
  }
}

/// Technique diagram for "cold_vs_hot_pan" — starting food in a cold pan
/// vs. a properly heated one.
class ColdVsHotPanPainter extends CustomPainter {
  const ColdVsHotPanPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scaffold = _TwoPanelPainter(
      wrongLabel: 'Cold pan',
      rightLabel: 'Hot pan',
      drawWrong: (canvas, panel) {
        final panRadius = panel.width * 0.42;
        final panCenter = Offset(panel.center.dx, panel.center.dy + 6);
        _panWithPieces(canvas, panel, AppDesignTokens.ctaTerracotta, [Offset.zero], panel.width * 0.13);
        _heatLines(canvas, panCenter, panRadius, AppDesignTokens.ctaTerracotta.withValues(alpha: 0.6), hot: false);
      },
      drawRight: (canvas, panel) {
        final panRadius = panel.width * 0.42;
        final panCenter = Offset(panel.center.dx, panel.center.dy + 6);
        _panWithPieces(canvas, panel, AppDesignTokens.deepForest, [Offset.zero], panel.width * 0.13);
        _heatLines(canvas, panCenter, panRadius, AppDesignTokens.deepForest, hot: true);
      },
    );
    scaffold.paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
