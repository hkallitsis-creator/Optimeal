import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/ledger_service.dart';
import 'package:optimeal/services/ledger_verdict.dart';

void main() {
  group('selectLedgerVerdict', () {
    test('no payload (demo recipe) is demo regardless of other state', () {
      expect(
        selectLedgerVerdict(hasPayload: false, isReCook: false, surface: CookModeSurface.fridgeClearer, result: const LedgerCompletionSuccess(ingredientsRescued: 1, ingredientsRescuedList: ['Onion'], lifetimeIngredientsRescued: 5)),
        LedgerVerdict.demo,
      );
      expect(
        selectLedgerVerdict(hasPayload: false, isReCook: true, surface: null, result: null),
        LedgerVerdict.demo,
      );
    });

    test('re-cook is notCountedReCook even if the original surface was rescue-eligible', () {
      expect(
        selectLedgerVerdict(hasPayload: true, isReCook: true, surface: CookModeSurface.fridgeClearer, result: null),
        LedgerVerdict.notCountedReCook,
      );
    });

    test('re-cook via Recently Cooked (surface null, isReCook true) is notCountedReCook, not notCountedWrongSurface', () {
      expect(
        selectLedgerVerdict(hasPayload: true, isReCook: true, surface: null, result: null),
        LedgerVerdict.notCountedReCook,
      );
    });

    test('a fresh cook from a non-rescue-eligible surface is notCountedWrongSurface', () {
      expect(
        selectLedgerVerdict(hasPayload: true, isReCook: false, surface: CookModeSurface.customAiRecipeCreator, result: null),
        LedgerVerdict.notCountedWrongSurface,
      );
      expect(
        selectLedgerVerdict(hasPayload: true, isReCook: false, surface: CookModeSurface.weeklyPlanner, result: null),
        LedgerVerdict.notCountedWrongSurface,
      );
    });

    test('a fresh cook with a null surface (not a re-cook) is notCountedWrongSurface', () {
      expect(
        selectLedgerVerdict(hasPayload: true, isReCook: false, surface: null, result: null),
        LedgerVerdict.notCountedWrongSurface,
      );
    });

    test('a fresh, rescue-eligible cook with a successful write is counted', () {
      expect(
        selectLedgerVerdict(
          hasPayload: true,
          isReCook: false,
          surface: CookModeSurface.fridgeClearer,
          result: const LedgerCompletionSuccess(ingredientsRescued: 2, ingredientsRescuedList: ['Onion', 'Carrot'], lifetimeIngredientsRescued: 10),
        ),
        LedgerVerdict.counted,
      );
    });

    test('a fresh, rescue-eligible cook with a failed write is writeFailedQueued', () {
      expect(
        selectLedgerVerdict(
          hasPayload: true,
          isReCook: false,
          surface: CookModeSurface.fridgeClearer,
          result: LedgerCompletionWriteFailed(payload: const {}, error: Exception('network')),
        ),
        LedgerVerdict.writeFailedQueued,
      );
    });
  });

  group('ledgerVerdictCopy', () {
    test('every non-counted, non-demo verdict has exactly one line of copy, under 15 words', () {
      for (final verdict in [
        LedgerVerdict.notCountedWrongSurface,
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

    test('notCountedWrongSurface copy names only Fridge Clearer, not the removed Fridge Countdown', () {
      final line = ledgerVerdictCopy[LedgerVerdict.notCountedWrongSurface]!;
      expect(line, contains('Fridge Clearer'));
      expect(line, isNot(contains('Fridge Countdown')));
    });

    test('counted and demo have no copy entry (handled by other UI, or no UI)', () {
      expect(ledgerVerdictCopy[LedgerVerdict.counted], isNull);
      expect(ledgerVerdictCopy[LedgerVerdict.demo], isNull);
    });
  });
}
