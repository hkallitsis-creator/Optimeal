import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/services/prep_step_detector.dart';

/// The dedup heuristic (R1).
///
/// Cook Mode has always prepended a synthesized mise step, and generations
/// routinely emit their own prep step too — so device builds showed both, back
/// to back, saying the same thing.
///
/// **A false positive deletes a real cooking step**, which is much worse than a
/// duplicate prep step. Every case below is written from that asymmetry.
bool _detect(String title, List<String> bullets,
        {List<String> ingredients = const ['onion', 'garlic', 'potatoes']}) =>
    looksLikeGeneratedPrepStep(
      title: title,
      bullets: bullets,
      ingredientNames: ingredients,
    );

void main() {
  group('detected as a generated prep step', () {
    test('the title the model actually produces', () {
      expect(
        _detect('Prepare Your Ingredients',
            ['Dice the onion.', 'Peel the potatoes.']),
        isTrue,
      );
    });

    test('the other prep-ish titles', () {
      for (final title in [
        'Prep the vegetables',
        'Preparation',
        'Mise en place',
        'Gather your ingredients',
        'Ingredients',
        'Set up your board',
        'Setup',
      ]) {
        expect(_detect(title, const ['Get everything ready.']), isTrue,
            reason: title);
      }
    });

    test('an unprep-titled step whose every bullet is just an ingredient', () {
      // The stricter second branch: no cooking verb anywhere AND every bullet
      // names a real ingredient from this recipe.
      expect(
        _detect('Before you start', [
          'Onion, peeled and halved',
          'Two cloves of garlic',
          'Potatoes, scrubbed',
        ]),
        isTrue,
      );
    });
  });

  group('NOT detected — a real cooking step is never deleted', () {
    test('a cooking verb overrides even a prep-ish title', () {
      // "Prep and sear the chicken" is a cooking step with a misleading name.
      // Deleting it would delete the sear.
      expect(
        _detect('Prep and sear the chicken',
            ['Season the chicken.', 'Sear it skin side down.']),
        isFalse,
      );
      expect(
        _detect('Prepare the pan', ['Heat the oil until it shimmers.']),
        isFalse,
      );
    });

    test('ordinary cooking steps', () {
      for (final title in [
        'Heat the oil',
        'Boil the pasta',
        'Simmer the sauce',
        'Roast in the oven',
        'Plate it up',
      ]) {
        expect(_detect(title, const ['Do the thing.']), isFalse, reason: title);
      }
    });

    test('a bullet that is not an ingredient breaks the strict branch', () {
      expect(
        _detect('Before you start', [
          'Onion, peeled',
          'Put a large bowl beside the board',
        ]),
        isFalse,
        reason: 'not every bullet names an ingredient',
      );
    });

    test('an empty or ingredient-less recipe cannot use the strict branch', () {
      expect(_detect('Before you start', const []), isFalse);
      expect(
        _detect('Before you start', const ['Onion'], ingredients: const []),
        isFalse,
      );
    });

  });

  test('plural and singular ingredient forms both match', () {
    expect(
      _detect('Before you start', const ['Potato, scrubbed'],
          ingredients: const ['potatoes']),
      isTrue,
    );
    expect(
      _detect('Before you start', const ['Potatoes, scrubbed'],
          ingredients: const ['potato']),
      isTrue,
    );
  });
}
