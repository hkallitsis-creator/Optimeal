import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/widgets/generation_loading_card.dart';
import 'package:optimeal/widgets/onboarding_visuals.dart';
import 'package:optimeal/widgets/spoon_bowl_illustration.dart';

/// The spoon-and-bowl illustration was drawn twice and the copies drifted: on
/// device, onboarding slide 1 rendered as a detached dome plus a floating
/// spoon, and the loading card's paddle crossed the bowl rim mid-stir.
void main() {
  group('geometry — the paddle never leaves the bowl', () {
    // Sampling the whole cycle, not the two or three phases someone happened
    // to look at. The clamp is derived from the rim rather than chosen, so
    // this should hold at every size as well as every phase.
    const sizes = [
      Size(176, 132),
      Size(96, 96),
      Size(320, 240),
      Size(134, 96),
    ];

    for (final size in sizes) {
      test('at ${size.width}x${size.height}, across the full cycle', () {
        final g = SpoonBowlGeometry(size);
        for (var i = 0; i <= 720; i++) {
          final t = i / 720;
          expect(g.paddleInsideRim(t), isTrue,
              reason: 'paddle left the rim ellipse at phase $t on $size');
        }
      });
    }

    test('the orbit is strictly inside the rim on both axes', () {
      const g = SpoonBowlGeometry(Size(176, 132));
      expect(g.orbitRx, lessThan(g.rimRx));
      expect(g.orbitRy, lessThan(g.rimRy));
      expect(g.orbitRy, greaterThan(0),
          reason: 'a zero vertical orbit would read as a flat slide, not a stir');
    });

    test('the rim is deeper than the paddle is tall', () {
      // The original bug in one line: rimRy was 0.09h while the paddle was
      // 0.13h tall, so the paddle could not fit inside the rim at any phase.
      const g = SpoonBowlGeometry(Size(176, 132));
      expect(g.rimRy * 2, greaterThan(g.paddleHeight));
    });

    test('the swing actually swings', () {
      const g = SpoonBowlGeometry(Size(176, 132));
      final xs = [for (var i = 0; i <= 60; i++) g.paddleCenterAt(i / 60).dx];
      expect(xs.reduce((a, b) => a > b ? a : b) -
              xs.reduce((a, b) => a < b ? a : b),
          greaterThan(g.rimRx * 0.5),
          reason: 'a clamped orbit must still be a visible stir');
    });

    test('the spoon spends time behind the batter and time in front', () {
      const g = SpoonBowlGeometry(Size(176, 132));
      final behind = [for (var i = 0; i <= 200; i++) g.isBehindAt(i / 200)];
      expect(behind.any((b) => b), isTrue);
      expect(behind.any((b) => !b), isTrue);
    });
  });

  group('one illustration, two surfaces', () {
    testWidgets('onboarding slide 1 uses the shared illustration',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: SpoonAndBowlIllustration())),
      ));

      expect(find.byType(SpoonBowlIllustration), findsOneWidget);
    });

    testWidgets('onboarding renders it static, at the shared frozen phase',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: SpoonAndBowlIllustration())),
      ));

      final widget =
          tester.widget<SpoonBowlIllustration>(find.byType(SpoonBowlIllustration));
      expect(widget.phase, SpoonBowlIllustration.staticPhase);
    });

    testWidgets('the loading card uses the shared illustration', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: GenerationLoadingCard(stage: GenerationStage.findingIdeas),
        ),
      ));
      await tester.pump();

      expect(find.byType(SpoonBowlIllustration), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
