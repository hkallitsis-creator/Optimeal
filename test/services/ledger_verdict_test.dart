import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/models/recipe_origin.dart';
import 'package:optimeal/services/ledger_service.dart';
import 'package:optimeal/services/ledger_verdict.dart';

void main() {
  group('selectLedgerVerdict', () {
    test('no payload (demo recipe) is demo regardless of other state', () {
      expect(
        selectLedgerVerdict(hasPayload: false, isReCook: false, origin: RecipeOrigin.fridgeClearer, result: const LedgerCompletionSuccess(ingredientsRescued: 1, ingredientsRescuedList: ['Onion'], lifetimeIngredientsRescued: 5)),
        LedgerVerdict.demo,
      );
      expect(
        selectLedgerVerdict(hasPayload: false, isReCook: true, origin: null, result: null),
        LedgerVerdict.demo,
      );
    });

    test('re-cook is notCountedReCook even for a Fridge Clearer recipe', () {
      expect(
        selectLedgerVerdict(hasPayload: true, isReCook: true, origin: RecipeOrigin.fridgeClearer, result: null),
        LedgerVerdict.notCountedReCook,
      );
    });

    test('re-cook of a recipe with no recorded origin is notCountedReCook, not notCountedNotFridgeRecipe', () {
      expect(
        selectLedgerVerdict(hasPayload: true, isReCook: true, origin: null, result: null),
        LedgerVerdict.notCountedReCook,
      );
    });

    test('a fresh cook of a non-Fridge-Clearer recipe is notCountedNotFridgeRecipe', () {
      expect(
        selectLedgerVerdict(hasPayload: true, isReCook: false, origin: RecipeOrigin.customAiRecipeCreator, result: null),
        LedgerVerdict.notCountedNotFridgeRecipe,
      );
    });

    test('a fresh cook of a recipe with no recorded origin is notCountedNotFridgeRecipe', () {
      // Legacy payloads (persisted before provenance existed) must degrade to
      // "not eligible" rather than being guessed into counting.
      expect(
        selectLedgerVerdict(hasPayload: true, isReCook: false, origin: null, result: null),
        LedgerVerdict.notCountedNotFridgeRecipe,
      );
    });

    test('a fresh Fridge Clearer cook with a successful write is counted', () {
      expect(
        selectLedgerVerdict(
          hasPayload: true,
          isReCook: false,
          origin: RecipeOrigin.fridgeClearer,
          result: const LedgerCompletionSuccess(ingredientsRescued: 2, ingredientsRescuedList: ['Onion', 'Carrot'], lifetimeIngredientsRescued: 10),
        ),
        LedgerVerdict.counted,
      );
    });

    test('a fresh Fridge Clearer cook with a failed write is writeFailedQueued', () {
      expect(
        selectLedgerVerdict(
          hasPayload: true,
          isReCook: false,
          origin: RecipeOrigin.fridgeClearer,
          result: LedgerCompletionWriteFailed(payload: const {}, error: Exception('network')),
        ),
        LedgerVerdict.writeFailedQueued,
      );
    });

    test('the verdict never depends on which screen launched the cook', () {
      // The regression this whole change exists for: the function no longer
      // accepts a surface at all, so a planner-launched cook and a
      // Fridge-Clearer-launched cook of the SAME recipe cannot diverge.
      const success = LedgerCompletionSuccess(ingredientsRescued: 1, ingredientsRescuedList: ['Zucchini'], lifetimeIngredientsRescued: 3);
      final launchedFromFridgeClearer = selectLedgerVerdict(hasPayload: true, isReCook: false, origin: RecipeOrigin.fridgeClearer, result: success);
      final launchedFromPlanner = selectLedgerVerdict(hasPayload: true, isReCook: false, origin: RecipeOrigin.fridgeClearer, result: success);
      expect(launchedFromPlanner, launchedFromFridgeClearer);
      expect(launchedFromPlanner, LedgerVerdict.counted);
    });
  });

  group('ledgerVerdictCopy', () {
    test('every non-counted, non-demo verdict has exactly one line of copy, under 15 words', () {
      for (final verdict in [
        LedgerVerdict.notCountedNotFridgeRecipe,
        LedgerVerdict.notCountedReCook,
        LedgerVerdict.writeFailedQueued,
      ]) {
        final line = ledgerVerdictCopy[verdict];
        expect(line, isNotNull, reason: '$verdict must have copy');
        expect(line!.trim(), isNotEmpty);
        final wordCount = line.trim().split(RegExp(r'\s+')).length;
        expect(wordCount, lessThan(15), reason: '"$line" is $wordCount words');
      }
    });

    test('notCountedNotFridgeRecipe copy names only Fridge Clearer, not the removed Fridge Countdown', () {
      final line = ledgerVerdictCopy[LedgerVerdict.notCountedNotFridgeRecipe]!;
      expect(line, contains('Fridge Clearer'));
      expect(line, isNot(contains('Fridge Countdown')));
    });

    test('counted and demo have no copy entry (handled by other UI, or no UI)', () {
      expect(ledgerVerdictCopy[LedgerVerdict.counted], isNull);
      expect(ledgerVerdictCopy[LedgerVerdict.demo], isNull);
    });
  });
}
