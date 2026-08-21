import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/models/fridge_idea.dart';

/// Stage 1 of the two-stage Fridge Clearer flow (2026-08-22).
///
/// The arithmetic tests matter more than the parsing ones: the clearance line
/// is the hero of every idea card, and it is the one number this feature must
/// never inflate. It is computed here, from the user's own list, precisely so
/// a model that writes "clears 4 of your 4" cannot make it true.

void main() {
  group('parseFridgeIdeasJson', () {
    test('reads the signed schema', () {
      final ideas = parseFridgeIdeasJson('''
        {"ideas":[
          {"title":"Zucchini Frittata","total_time_minutes":20,
           "ingredients_cleared":["Zucchini","Eggs"],"ingredients_left":[]},
          {"title":"Potato Hash","total_time_minutes":35,
           "ingredients_cleared":["Potatoes"],"ingredients_left":["Eggs"]}
        ]}
      ''');

      expect(ideas, hasLength(2));
      expect(ideas!.first.title, 'Zucchini Frittata');
      expect(ideas.first.totalTimeMinutes, 20);
      expect(ideas.first.ingredientsCleared, ['Zucchini', 'Eggs']);
    });

    test('accepts a bare array as well as the wrapped object', () {
      final ideas = parseFridgeIdeasJson(
          '[{"title":"Soup","total_time_minutes":15,"ingredients_cleared":[]}]');
      expect(ideas, hasLength(1));
      expect(ideas!.single.title, 'Soup');
    });

    test('caps at three even if the model over-delivers', () {
      final ideas = parseFridgeIdeasJson('''
        {"ideas":[{"title":"A"},{"title":"B"},{"title":"C"},{"title":"D"}]}
      ''');
      expect(ideas, hasLength(3));
      expect(ideas!.map((i) => i.title), ['A', 'B', 'C']);
    });

    test('accepts fewer than three rather than failing the screen', () {
      // Two real choices beat an error card.
      final ideas =
          parseFridgeIdeasJson('{"ideas":[{"title":"A"},{"title":"B"}]}');
      expect(ideas, hasLength(2));
    });

    test('skips entries with no usable title', () {
      final ideas = parseFridgeIdeasJson(
          '{"ideas":[{"title":"  "},{"title":"Real Dish"},{"total_time_minutes":9}]}');
      expect(ideas, hasLength(1));
      expect(ideas!.single.title, 'Real Dish');
    });

    test('a missing time is 0, not a crash and not an invented number', () {
      final ideas = parseFridgeIdeasJson('{"ideas":[{"title":"A"}]}');
      expect(ideas!.single.totalTimeMinutes, 0);
    });

    group('returns null rather than fabricating', () {
      // The chosen fallback. This screen used to invent a hardcoded recipe
      // when parsing failed (CLAUDE.md roadmap item 20); a fabricated MENU
      // would be worse still, because a made-up idea then anchors a real
      // stage-2 generation. Null surfaces the error card with a retry.
      test('on malformed JSON', () {
        expect(parseFridgeIdeasJson('{"ideas": [ {"title": '), isNull);
      });
      test('on prose instead of JSON', () {
        expect(parseFridgeIdeasJson('Sure! Here are three ideas...'), isNull);
      });
      test('on empty input', () {
        expect(parseFridgeIdeasJson('   '), isNull);
      });
      test('on valid JSON of the wrong shape', () {
        expect(parseFridgeIdeasJson('{"recipes":[{"title":"A"}]}'), isNull);
      });
      test('on an ideas array with nothing usable in it', () {
        expect(parseFridgeIdeasJson('{"ideas":[{"foo":1},{"title":""}]}'),
            isNull);
      });
    });
  });

  group('FridgeClearance arithmetic', () {
    const entered = ['Zucchini', 'Eggs', 'Potatoes', 'Cheese'];

    test('clears everything', () {
      final c = FridgeClearance.forIdea(
        const FridgeIdea(
          title: 'Everything Bake',
          totalTimeMinutes: 30,
          ingredientsCleared: ['Zucchini', 'Eggs', 'Potatoes', 'Cheese'],
        ),
        entered,
      );
      expect(c.clearedCount, 4);
      expect(c.enteredCount, 4);
      expect(c.left, isEmpty);
      expect(c.clearsEverything, isTrue);
    });

    test('leaves one behind — the "X stays" case', () {
      final c = FridgeClearance.forIdea(
        const FridgeIdea(
          title: 'Frittata',
          totalTimeMinutes: 20,
          ingredientsCleared: ['Zucchini', 'Eggs', 'Cheese'],
        ),
        entered,
      );
      expect(c.clearedCount, 3);
      expect(c.left, ['Potatoes']);
      expect(c.clearsEverything, isFalse);
    });

    test('an ingredient the user never entered cannot count', () {
      // The loop iterates the ENTERED list, so a hallucinated ingredient has
      // nothing to match against and inflates nothing.
      final c = FridgeClearance.forIdea(
        const FridgeIdea(
          title: 'Padded',
          totalTimeMinutes: 10,
          ingredientsCleared: ['Zucchini', 'Saffron', 'Lobster', 'Truffle'],
        ),
        entered,
      );
      expect(c.clearedCount, 1);
      expect(c.left, ['Eggs', 'Potatoes', 'Cheese']);
    });

    test('an empty cleared list clears nothing', () {
      final c = FridgeClearance.forIdea(
        const FridgeIdea(
            title: 'Nothing', totalTimeMinutes: 5, ingredientsCleared: []),
        entered,
      );
      expect(c.clearedCount, 0);
      expect(c.left, entered);
    });

    test('matching survives case, plurals and compound names', () {
      final c = FridgeClearance.forIdea(
        const FridgeIdea(
          title: 'Loose Match',
          totalTimeMinutes: 25,
          // "potato" vs "Potatoes", "bread" vs "Stale Bread", "EGGS" vs "Eggs".
          ingredientsCleared: ['potato', 'bread', 'EGGS'],
        ),
        const ['Eggs', 'Potatoes', 'Stale Bread', 'Cheese'],
      );
      expect(c.cleared, ['Eggs', 'Potatoes', 'Stale Bread']);
      expect(c.left, ['Cheese']);
    });

    test('the user\'s own order and wording are preserved', () {
      final c = FridgeClearance.forIdea(
        const FridgeIdea(
            title: 'X',
            totalTimeMinutes: 1,
            ingredientsCleared: ['cheese', 'zucchini']),
        entered,
      );
      // Not re-sorted, not re-cased to the model's spelling.
      expect(c.cleared, ['Zucchini', 'Cheese']);
    });

    test('an empty match on either side never counts', () {
      expect(FridgeClearance.matches('', 'Eggs'), isFalse);
      expect(FridgeClearance.matches('Eggs', '   '), isFalse);
    });
  });
}
