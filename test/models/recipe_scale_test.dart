import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/models/recipe_scale.dart';

/// The servings maths behind the overview's stepper.
///
/// The device evidence this exists to fix: rows reading "4 piece Eggs" and
/// "0.3 tsp Black Pepper" — a unit word no cook says, and a precision no
/// kitchen can measure.
RecipeIngredient _ing(String name, double amount, String unit) =>
    RecipeIngredient(name: name, amount: amount, unit: unit);

List<ScaledIngredient> _scale(
  List<RecipeIngredient> ingredients, {
  int? basePortions = 2,
  required int servings,
}) =>
    scaleIngredients(
      ingredients: ingredients,
      basePortions: basePortions,
      servings: servings,
    );

void main() {
  group('the whole-piece rule', () {
    test('eggs at 1.5 become 2, and say why', () {
      final out = _scale([_ing('eggs', 1.0, 'piece')], servings: 3);
      expect(out.single.displayAmount, '2');
      expect(out.single.roundedUp, isTrue);
      expect(out.single.displayLine, '2 eggs');
    });

    test('the unit word "piece" never renders', () {
      final out = _scale([_ing('Eggs', 4, 'piece')], servings: 2);
      expect(out.single.displayLine, '4 Eggs');
      expect(out.single.displayLine, isNot(contains('piece')));
    });

    test('no hint when rounding changed nothing', () {
      final out = _scale([_ing('eggs', 2, 'piece')], servings: 4);
      expect(out.single.displayAmount, '4');
      expect(out.single.roundedUp, isFalse,
          reason: 'a clean double is not a rounding event');
    });

    test('cloves and slices are countable too, and so is a bare unit', () {
      final out = _scale([
        _ing('garlic', 1, 'clove'),
        _ing('bread', 1, 'slice'),
        _ing('lemons', 1, ''),
      ], servings: 3);

      for (final row in out) {
        expect(row.displayAmount, '2');
        expect(row.roundedUp, isTrue);
      }
    });
  });

  group('non-count units', () {
    test('250 g at three-quarters reads 190 g', () {
      final out =
          _scale([_ing('potatoes', 250, 'g')], basePortions: 4, servings: 3);
      expect(out.single.displayLine, '190 g potatoes',
          reason: '187.5 g is a precision no one can weigh');
    });

    test('bulk values under 100 keep one decimal', () {
      final out = _scale([_ing('flour', 30, 'g')], basePortions: 4, servings: 3);
      expect(out.single.displayAmount, '22.5 g');
    });

    test('trailing .0 is dropped', () {
      final out = _scale([_ing('milk', 50, 'ml')], servings: 2);
      expect(out.single.displayAmount, '50 ml');
    });

    test('half a tablespoon is a fraction, not a decimal', () {
      final out = _scale([_ing('olive oil', 1, 'tbsp')], servings: 1);
      expect(out.single.displayAmount, '½ tbsp');
    });

    test('quarters and mixed fractions on spoons', () {
      expect(
        _scale([_ing('salt', 1, 'tsp')], basePortions: 4, servings: 1)
            .single
            .displayAmount,
        '¼ tsp',
      );
      expect(
        _scale([_ing('salt', 1, 'tsp')], basePortions: 2, servings: 3)
            .single
            .displayAmount,
        '1½ tsp',
      );
    });

    test('the 0.3 tsp case is not made worse', () {
      // Never becomes a fraction glyph it does not equal.
      final out = _scale([_ing('black pepper', 0.3, 'tsp')], servings: 2);
      expect(out.single.displayAmount, '0.3 tsp');
    });
  });

  group('a recipe with no declared basePortions', () {
    test('renders as generated and never crashes', () {
      final out =
          _scale([_ing('rice', 200, 'g')], basePortions: null, servings: 5);
      expect(out.single.displayAmount, '200 g',
          reason: 'nothing to scale FROM, so nothing is scaled');
    });

    test('a zero basePortions is treated the same, not divided by', () {
      final out =
          _scale([_ing('rice', 200, 'g')], basePortions: 0, servings: 5);
      expect(out.single.displayAmount, '200 g');
    });
  });

  group('default servings precedence (R5)', () {
    test('planner context wins when present', () {
      expect(
        defaultServingsFor(
          plannerServings: 5,
          profileHouseholdServings: 2,
          recipeBasePortions: 4,
        ),
        5,
      );
    });

    test('profile household wins when there is no planner context', () {
      expect(
        defaultServingsFor(
          plannerServings: null,
          profileHouseholdServings: 3,
          recipeBasePortions: 4,
        ),
        3,
      );
    });

    test('the recipe basePortions is the last resort', () {
      expect(
        defaultServingsFor(
          plannerServings: null,
          profileHouseholdServings: null,
          recipeBasePortions: 4,
        ),
        4,
      );
    });

    test('the result is clamped into range', () {
      expect(
        defaultServingsFor(recipeBasePortions: 99, profileHouseholdServings: null),
        kServingsMax,
      );
      expect(defaultServingsFor(recipeBasePortions: 0), kServingsMin);
    });

    test('a big household extends the ceiling rather than being clamped away',
        () {
      expect(servingsCeilingFor(householdServings: 8), 8);
      expect(servingsCeilingFor(householdServings: 2), kServingsMax);
      expect(
        defaultServingsFor(profileHouseholdServings: 8, recipeBasePortions: 2),
        8,
      );
    });
  });

  test('the meta line total ignores negative durations', () {
    expect(estimatedMinutes([5, 10, 0]), 15);
    expect(estimatedMinutes([5, -3]), 5);
  });
}
