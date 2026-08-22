import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/data/diagram_keys.dart';
import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/cut_key_resolver.dart';
import 'package:optimeal/widgets/diagram_sheet.dart';

RecipeIngredient _ing(String name, {String? cut}) =>
    RecipeIngredient(name: name, amount: 1, unit: 'piece', cut: cut);

CookModeStepPayload _step(String title, {List<String> bullets = const [], List<String>? adds}) =>
    CookModeStepPayload(
      title: title,
      heat: 'medium',
      durationMinutes: 5,
      bullets: bullets,
      ingredientsAdded: adds,
    );

void main() {
  group('the declared cut wins', () {
    // The brief said RecipeIngredient has no cut key. It does — the parser
    // validates it against the closed vocabulary on the way in — so the
    // model's own statement is used before any text inference.
    test('a declared cut is returned as-is', () {
      expect(resolveCutKey(ingredient: _ing('carrot', cut: 'julienne')),
          'julienne');
    });

    test('a declared cut beats contradicting step prose', () {
      final key = resolveCutKey(
        ingredient: _ing('carrot', cut: 'julienne'),
        steps: [_step('Roughly chop the carrot')],
      );
      expect(key, 'julienne');
    });

    test('the explicit "none" is an absence, not a cut', () {
      expect(resolveCutKey(ingredient: _ing('salt', cut: 'none')), isNull);
    });
  });

  group('the text fallback', () {
    test('reads the ingredient name', () {
      expect(resolveCutKey(ingredient: _ing('carrots, julienned')), 'julienne');
    });

    test('reads step prose, but only from steps naming the ingredient', () {
      final key = resolveCutKey(
        ingredient: _ing('parsley'),
        steps: [
          _step('Dice the onion'),
          _step('Tear the parsley over the top'),
        ],
      );
      expect(key, 'torn',
          reason: 'the onion step must not put a dice pill on the parsley');
    });

    test('a cut in another sentence of the same step does not attach', () {
      // Found on real dev output: a step that thinly sliced the potatoes and
      // seasoned with salt in the same breath put a `thin_slice` pill on the
      // SALT; another put `wedges` on the feta because lemon wedges were
      // mentioned nearby.
      final salt = resolveCutKey(
        ingredient: _ing('salt'),
        steps: [
          _step('Prepare',
              bullets: ['Thinly slice the potatoes. Season with salt.']),
        ],
      );
      expect(salt, isNull);

      final feta = resolveCutKey(
        ingredient: _ing('feta'),
        steps: [
          _step('Finish',
              bullets: ['Cut the lemon into wedges; crumble the feta over.']),
        ],
      );
      expect(feta, isNull);
    });

    test('a cut in the SAME sentence still attaches', () {
      final potato = resolveCutKey(
        ingredient: _ing('potatoes'),
        steps: [
          _step('Prepare',
              bullets: ['Thinly slice the potatoes. Season with salt.']),
        ],
      );
      expect(potato, 'thin_slice');
    });

    test('an ingredient no step mentions gets nothing', () {
      final key = resolveCutKey(
        ingredient: _ing('saffron'),
        steps: [_step('Finely dice the shallot')],
      );
      expect(key, isNull);
    });

    test('matching is whole-word', () {
      // "dicey", "chopstick", "grateful" must not match.
      expect(resolveCutKey(ingredient: _ing('a dicey situation')), isNull);
      expect(resolveCutKey(ingredient: _ing('chopsticks')), isNull);
      expect(resolveCutKey(ingredient: _ing('grateful garnish')), isNull);
    });

    test('the longest phrase wins over a shorter one inside it', () {
      expect(resolveCutKey(ingredient: _ing('onion, finely diced')),
          'small_dice');
      expect(resolveCutKey(ingredient: _ing('onion, diced')), 'medium_dice');
    });

    test('plural head nouns still find their step', () {
      final key = resolveCutKey(
        ingredient: _ing('spring onions'),
        steps: [_step('Thinly slice the spring onion')],
      );
      expect(key, 'thin_slice');
    });
  });

  group('what the resolver may never return', () {
    test('every key it can produce is in the cut vocabulary', () {
      for (final key in kCutSynonyms.keys) {
        expect(ingredientCutVocabulary, contains(key),
            reason: '"$key" is not a signed cut value');
      }
    });

    test('no technique diagram key can ever attach to an ingredient row', () {
      for (final technique in techniqueDiagramKeys) {
        expect(kCutSynonyms.containsKey(technique), isFalse,
            reason: '"$technique" is a fact about a pan, not about food');
      }

      // And not by accident through prose either.
      final key = resolveCutKey(
        ingredient: _ing('chicken'),
        steps: [
          _step('Do not crowd the pan',
              bullets: ['give the chicken room', 'use a cold pan']),
        ],
      );
      expect(techniqueDiagramKeys, isNot(contains(key)));
    });

    test('the pill form only returns keys with a BUILT diagram', () {
      // julienne is built; medium_dice is a valid key with no painter.
      expect(
        resolveCutDiagramKey(ingredient: _ing('carrot', cut: 'julienne')),
        'julienne',
      );
      expect(
        resolveCutDiagramKey(ingredient: _ing('onion', cut: 'medium_dice')),
        isNull,
        reason: 'a valid but unbuilt key renders no pill, not a broken one',
      );

      // Whatever the pill form returns, a diagram exists for it.
      for (final key in kCutSynonyms.keys) {
        final resolved =
            resolveCutDiagramKey(ingredient: _ing('x', cut: key));
        if (resolved != null) expect(diagramFor(resolved), isNotNull);
      }
    });

    test('"whole" and "none" are not text-matchable', () {
      // "whole" appears in prose constantly and says nothing about knife work.
      expect(kCutSynonyms.containsKey('whole'), isFalse);
      expect(kCutSynonyms.containsKey('none'), isFalse);
      expect(
        resolveCutKey(
          ingredient: _ing('chicken'),
          steps: [_step('Cook the chicken whole for the whole time')],
        ),
        isNull,
      );
    });
  });
}
