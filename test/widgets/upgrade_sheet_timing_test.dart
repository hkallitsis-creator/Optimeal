import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/services/upgrade_nudge_gate.dart';
import 'package:optimeal/widgets/upgrade_prompt_sheet.dart';

/// A sales sheet must never interrupt an active cook path — pre-cook through
/// post-cook verdict.
///
/// This shipped broken: the post-cook nudge was presented from inside Cook
/// Mode's completion sequence, *before* the verdict sheet, so a
/// celebration-styled sales interstitial landed on top of an unfinished cook.
void main() {
  setUp(UpgradeNudgeGate.resetForTest);
  tearDown(UpgradeNudgeGate.resetForTest);

  Future<void> pumpAndTryToShow(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => UpgradePromptSheet.show(
                context,
                title: 'Unlimited recipes with Pro',
                message: 'Pro removes the weekly generation limit.',
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet refuses to appear while a cook is active',
      (tester) async {
    UpgradeNudgeGate.enterCookPath();
    await pumpAndTryToShow(tester);

    expect(find.text('Unlimited recipes with Pro'), findsNothing,
        reason: 'a sales sheet must not interrupt a cook');
    expect(find.text('Upgrade to Pro'), findsNothing);
  });

  testWidgets('the sheet appears once the cook path has closed',
      (tester) async {
    UpgradeNudgeGate.enterCookPath();
    UpgradeNudgeGate.exitCookPath();
    await pumpAndTryToShow(tester);

    expect(find.text('Unlimited recipes with Pro'), findsOneWidget);
  });

  testWidgets('no star glyph and no celebration headline', (tester) async {
    await pumpAndTryToShow(tester);

    expect(find.byIcon(Icons.star_rounded), findsNothing,
        reason: 'the celebration styling was the other half of the defect');
    expect(find.text('Nice cooking!'), findsNothing);
  });

  group('the gate', () {
    test('a scheduled nudge is consumable exactly once', () {
      expect(UpgradeNudgeGate.hasPendingPostCookNudge, isFalse);
      UpgradeNudgeGate.schedulePostCookNudge('cook_a');

      expect(UpgradeNudgeGate.hasPendingPostCookNudge, isTrue);
      expect(UpgradeNudgeGate.consumePendingPostCookNudge(), isTrue);
      expect(UpgradeNudgeGate.consumePendingPostCookNudge(), isFalse,
          reason: 'a rebuild must not be able to show the sheet twice');
      expect(UpgradeNudgeGate.hasPendingPostCookNudge, isFalse);
    });

    test('consuming nothing is safe', () {
      expect(UpgradeNudgeGate.consumePendingPostCookNudge(), isFalse);
    });

    test('a nudge scheduled during a cook survives until the cook ends', () {
      UpgradeNudgeGate.enterCookPath();
      UpgradeNudgeGate.schedulePostCookNudge('cook_b');

      // Home would decline to consume it here, leaving it pending.
      expect(UpgradeNudgeGate.isCookPathActive, isTrue);
      expect(UpgradeNudgeGate.hasPendingPostCookNudge, isTrue);

      UpgradeNudgeGate.exitCookPath();
      expect(UpgradeNudgeGate.consumePendingPostCookNudge(), isTrue,
          reason: 'deferred, not swallowed');
    });
  });
}
