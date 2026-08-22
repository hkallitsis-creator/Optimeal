import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/widgets/post_cook_share_card.dart';

/// # PERMANENT until CH+EU trademark clearance. Do not weaken.
///
/// The standing rule is that **no public branding appears on any name before
/// clearance**. The share card is the one surface in the app that leaves the
/// device and lands in front of strangers, so it is the surface where that
/// rule actually bites.
///
/// This shipped broken once: the card rendered an "OPTIMEAL" wordmark and a
/// leaf logo, the share text carried "#OptiMeal", and the exported file was
/// named `optimeal_recap_*.png`. All three were public branding.
///
/// If this test fails, the fix is to remove the branding — never to relax the
/// pattern. The branding slot in the layout stays; it just stays empty.
void main() {
  const forbidden = r'optimeal|empyria|instinkt';
  final pattern = RegExp(forbidden, caseSensitive: false);

  Future<void> pumpCard(
    WidgetTester tester, {
    required List<String> rescued,
    required List<String> techniques,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostCookShareCardSheet(
            dishName: 'Chicken and Rice',
            ingredientsRescued: rescued,
            techniqueTitles: techniques,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  List<String> visibleStrings(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .where((s) => s.isNotEmpty)
      .toList();

  testWidgets('a rescue-counted share card renders no branding', (tester) async {
    await pumpCard(
      tester,
      rescued: ['courgette', 'spring onion'],
      techniques: ['Sautéing'],
    );

    for (final s in visibleStrings(tester)) {
      expect(pattern.hasMatch(s), isFalse,
          reason: 'branding string on the share surface: "$s"');
    }
  });

  testWidgets('a not-counted share card renders no branding', (tester) async {
    await pumpCard(tester, rescued: const [], techniques: ['Braising']);

    for (final s in visibleStrings(tester)) {
      expect(pattern.hasMatch(s), isFalse,
          reason: 'branding string on the share surface: "$s"');
    }
  });

  testWidgets('a not-counted cook can still be shared, without a rescue chip',
      (tester) async {
    await pumpCard(tester, rescued: const [], techniques: ['Braising']);

    final strings = visibleStrings(tester);
    expect(strings, contains('Chicken and Rice'));
    expect(strings.any((s) => s.contains('learned properly')), isTrue);
    expect(strings.any((s) => s.contains('rescued')), isFalse,
        reason: 'no rescue chip on a cook that did not count');
    expect(strings, isNot(contains(kShareStoryLine)),
        reason: 'the fridge story line would be untrue here');
  });

  test('the technique chip never conjugates the technique name', () {
    // This shipped as "learned to sautéing".
    expect(techniqueChipLabel('Sautéing'), 'sautéing, learned properly');
    expect(techniqueChipLabel('Braising'), 'braising, learned properly');
    expect(techniqueChipLabel('Stir-fry'), 'stir-fry, learned properly');

    for (final t in ['Sautéing', 'Braising', 'Roasting', 'Stir-fry']) {
      expect(techniqueChipLabel(t), isNot(contains('learned to')));
    }
  });

  test('the rescue chip pluralises', () {
    expect(rescueChipLabel(1), '1 ingredient rescued');
    expect(rescueChipLabel(3), '3 ingredients rescued');
  });
}
