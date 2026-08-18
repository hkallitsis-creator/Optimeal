import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/services/ledger_service.dart';

void main() {
  group('LedgerService.computeRescuedIngredients — provenance rule (F13)', () {
    test('an entered fresh item that appears in the cook counts (the potato case)', () {
      // Potatoes were wrongly excluded by the old freshProduceOnly
      // blocklist despite being genuinely perishable — the new rule has
      // no such blanket exclusion, so a real potato the user entered and
      // actually cooked now counts.
      final result = LedgerService.computeRescuedIngredients(
        enteredIngredients: ['Potatoes'],
        cookedIngredients: ['300g Potatoes (diced)'],
      );
      expect(result, ['Potatoes']);
    });

    test('an entered pantry staple is excluded even though it was entered and cooked', () {
      final result = LedgerService.computeRescuedIngredients(
        enteredIngredients: ['Salt', 'Zucchini'],
        cookedIngredients: ['1 tsp Salt', '300g Zucchini'],
      );
      expect(result, ['Zucchini']);
    });

    test('an ingredient the recipe added by itself never counts, even if fresh', () {
      // "Eggs" appears in the cooked recipe but was never entered by the
      // user — the recipe added it on its own initiative.
      final result = LedgerService.computeRescuedIngredients(
        enteredIngredients: ['Zucchini'],
        cookedIngredients: ['300g Zucchini', '2 Eggs'],
      );
      expect(result, ['Zucchini']);
      expect(result, isNot(contains('Eggs')));
    });

    test('an entered ingredient that never appears in the cook does not count', () {
      final result = LedgerService.computeRescuedIngredients(
        enteredIngredients: ['Zucchini', 'Spinach'],
        cookedIngredients: ['300g Zucchini'],
      );
      expect(result, ['Zucchini']);
    });

    test('empty entered ingredients yields no rescued ingredients regardless of the cook', () {
      final result = LedgerService.computeRescuedIngredients(
        enteredIngredients: const [],
        cookedIngredients: ['300g Zucchini', '2 Eggs'],
      );
      expect(result, isEmpty);
    });

    test('matching is case-insensitive substring against amount/prep-note strings', () {
      final result = LedgerService.computeRescuedIngredients(
        enteredIngredients: ['zucchini'],
        cookedIngredients: ['300g ZUCCHINI (diced small)'],
      );
      expect(result, ['zucchini']);
    });
  });
}
