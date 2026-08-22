import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/data/allergen_synonyms.dart';
import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/allergen_guard.dart';

/// The deterministic half of allergen enforcement.
///
/// The prompt instruction works on real dev output — a profile avoiding egg,
/// dairy and tree nuts, handed "eggs, cheese, walnuts", still produced a clean
/// recipe. That is the model complying, not a guarantee. This is the part that
/// does not depend on the model having a good day.

CookModeRecipePayload _recipe(List<String> ingredientNames) =>
    CookModeRecipePayload(
      title: 'Test dish',
      ingredients: ingredientNames,
      steps: const [
        CookModeStepPayload(
            title: 'Cook', heat: 'medium', durationMinutes: 5, bullets: []),
      ],
      structuredIngredients: [
        for (final n in ingredientNames)
          RecipeIngredient(name: n, amount: 1, unit: 'piece'),
      ],
      basePortions: 2,
    );

void main() {
  group('detection', () {
    test('a hit on an avoided allergen is found', () {
      final v = findAllergenViolations(
        recipe: _recipe(['potatoes', 'walnuts', 'spinach']),
        avoided: const ['Tree Nuts'],
      );
      expect(v, hasLength(1));
      expect(v.single.allergenLabel, 'Tree Nuts');
      expect(v.single.ingredientName, 'walnuts');
      expect(v.single.matchedWord, 'walnut');
    });

    test('a clean recipe is a no-op', () {
      expect(
        findAllergenViolations(
          recipe: _recipe(['potatoes', 'spinach', 'olive oil']),
          avoided: const ['Tree Nuts', 'Egg', 'Lactose/Dairy'],
        ),
        isEmpty,
      );
    });

    test('an allergen the user did NOT select is never checked', () {
      expect(
        findAllergenViolations(
          recipe: _recipe(['walnuts', 'cheese']),
          avoided: const ['Fish'],
        ),
        isEmpty,
        reason: 'this can only ever report something the user asked to avoid',
      );
    });

    test('no avoided allergens means no work at all', () {
      expect(
        findAllergenViolations(
          recipe: _recipe(['eggs', 'cheese', 'walnuts']),
          avoided: const [],
        ),
        isEmpty,
      );
    });

    test('several allergens on several ingredients are all reported', () {
      final v = findAllergenViolations(
        recipe: _recipe(['eggs', 'parmesan', 'hazelnuts', 'potatoes']),
        avoided: const ['Egg', 'Lactose/Dairy', 'Tree Nuts'],
      );
      expect(v.map((e) => e.allergenLabel).toSet(),
          {'Egg', 'Lactose/Dairy', 'Tree Nuts'});
    });

    test('unstructured recipes fall back to the display strings', () {
      const recipe = CookModeRecipePayload(
        title: 'Old saved recipe',
        ingredients: ['200 g cheddar', '2 potatoes'],
        steps: [
          CookModeStepPayload(
              title: 'Cook', heat: 'medium', durationMinutes: 5, bullets: []),
        ],
      );
      final v = findAllergenViolations(
          recipe: recipe, avoided: const ['Lactose/Dairy']);
      expect(v, hasLength(1));
      expect(v.single.matchedWord, 'cheddar');
    });
  });

  group('whole-word matching, and the substrings it must not catch', () {
    test('"nutritional yeast" is not a tree nut', () {
      // This is not hypothetical: nutritional yeast appeared in real dev
      // output as the vegan SUBSTITUTE for parmesan, for exactly the profile
      // that avoids dairy. A substring matcher would flag the substitute as
      // the allergen it replaces.
      expect(allergensIn('nutritional yeast', const ['Tree Nuts']), isEmpty);
      expect(allergensIn('nutmeg', const ['Tree Nuts']), isEmpty);
    });

    test('other near-misses stay clean', () {
      expect(allergensIn('coconut milk', const ['Tree Nuts']), isEmpty,
          reason: 'coconut is not on the tree-nut list');
      expect(allergensIn('buttermilk squash', const ['Lactose/Dairy']),
          contains('Lactose/Dairy'),
          reason: 'buttermilk is genuinely dairy — this one SHOULD fire');
      expect(allergensIn('eggplant', const ['Egg']), isEmpty,
          reason: '"eggplant" is not an egg');
    });

    test('plurals match', () {
      for (final name in ['egg', 'eggs', 'Egg', 'EGGS']) {
        expect(allergensIn(name, const ['Egg']), contains('Egg'), reason: name);
      }
    });

    test('multi-word synonyms match', () {
      expect(allergensIn('soy sauce', const ['Soy']), contains('Soy'));
      expect(allergensIn('pine nuts', const ['Tree Nuts']), contains('Tree Nuts'));
    });
  });

  group('the correction note', () {
    test('names the ingredient, the allergen and the matched word', () {
      final v = findAllergenViolations(
        recipe: _recipe(['grated parmesan']),
        avoided: const ['Lactose/Dairy'],
      );
      final note = buildAllergenCorrectionNote(v);

      expect(note, contains('ALLERGEN CORRECTION REQUIRED'));
      expect(note, contains('grated parmesan'));
      expect(note, contains('Lactose/Dairy'));
      expect(note, contains('do not'));
    });

    test('a clean list builds no note', () {
      expect(buildAllergenCorrectionNote(const []), isEmpty);
    });
  });

  group('the synonym table', () {
    // The 14 keys are not a draft — they are exactly what ProfileScreen
    // offers. Renaming a chip must not silently orphan its synonyms.
    const profileOptions = <String>[
      'Gluten',
      'Lactose/Dairy',
      'Tree Nuts',
      'Peanuts',
      'Fish',
      'Crustaceans',
      'Molluscs',
      'Soy',
      'Sesame',
      'Celery',
      'Mustard',
      'Sulfites/Alcohol',
      'Lupin',
      'Egg',
    ];

    test('every Profile chip has a synonym list', () {
      for (final option in profileOptions) {
        expect(kAllergenSynonymsDraft.containsKey(option), isTrue,
            reason: '"$option" has no synonyms — it would be unenforceable');
      }
    });

    test('there are no orphan keys', () {
      expect(kAllergenSynonymsDraft.keys.toSet(), profileOptions.toSet());
    });

    test('no synonym list is empty', () {
      kAllergenSynonymsDraft.forEach((label, words) {
        expect(words, isNotEmpty, reason: label);
      });
    });
  });
}
