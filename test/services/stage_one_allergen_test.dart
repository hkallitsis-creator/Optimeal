import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/services/allergen_guard.dart';

/// Part 4 — the stage-1 ideas allergen leak.
///
/// On a real dev run, a profile avoiding egg, dairy and tree nuts was offered
/// "Cheesy Potato Skillet" and "Spinach Walnut Salad". Stage 2 then produced a
/// clean recipe, so nothing unsafe was ever cooked — but the ideas screen is
/// the menu, and putting a dish someone cannot eat on their menu is the
/// surface working against the profile they filled in.
void main() {
  final code = File('lib/screens/fridge_clearer_screen.dart').readAsStringSync();

  group('PREVENT — the profile reaches stage 1', () {
    test('the ideas call passes the profile, same as stage 2', () {
      final start = code.indexOf('_generateIdeasWithAllergenFilter');
      expect(start, greaterThan(0));
      final helper = code.substring(start, start + 2500);
      expect(helper.contains('profile: profile'), isTrue);
      expect(helper.contains('staticPromptBlock: buildFridgeIdeasStaticPrompt()'),
          isTrue);
    });
  });

  group('DETECT — flagged ideas are dropped, never annotated', () {
    test('the real leaked titles are caught', () {
      const avoided = ['Egg', 'Lactose/Dairy', 'Tree Nuts'];

      expect(allergensInIdeaText('Cheesy Potato Skillet', avoided),
          contains('Lactose/Dairy'));
      expect(allergensInIdeaText('Spinach Walnut Salad', avoided),
          contains('Tree Nuts'));
      expect(allergensInIdeaText('Spinach Potato Bake', avoided), isEmpty,
          reason: 'the clean one survives');
    });

    test('ingredient hints are checked as well as the title', () {
      const avoided = ['Tree Nuts'];
      // A title that gives nothing away, with the allergen in the hints.
      expect(
        allergensInIdeaText('Autumn Salad pear rocket walnuts', avoided),
        contains('Tree Nuts'),
      );
    });

    test('an empty avoid list does no filtering at all', () {
      expect(allergensInIdeaText('Cheesy Potato Skillet', const []), isEmpty);
    });

    test('flagged ideas are dropped, not labelled', () {
      // 4b/4c: there is no annotate path. A flagged idea never renders.
      expect(code.contains('dropped.add(idea.title)'), isTrue);
      expect(code.toLowerCase().contains('contains dairy'), isFalse,
          reason: 'never show an annotated unsafe card');
    });
  });

  group('the <3 branch', () {
    test('exactly ONE silent retry, with the dropped titles excluded', () {
      final start = code.indexOf('_generateIdeasWithAllergenFilter');
      final helper = code.substring(start, code.indexOf('Future<void> _generateIdeas()'));

      expect(helper.contains('if (safe.length < 3 && dropped.isNotEmpty)'), isTrue);
      expect(helper.contains('attempt(List<String>.from(dropped))'), isTrue,
          reason: 'the retry excludes what was dropped, so it cannot re-offer it');

      // One retry, not a loop.
      expect(RegExp(r'await attempt\(').allMatches(helper).length, 2,
          reason: 'the first call plus exactly one retry');
    });

    test('survivors are shown even if fewer than three', () {
      final start = code.indexOf('_generateIdeasWithAllergenFilter');
      final helper = code.substring(start, code.indexOf('Future<void> _generateIdeas()'));
      expect(helper.contains('return safe.take(3).toList(growable: false)'), isTrue,
          reason: 'whatever survived is returned; one good idea beats an error');
    });

    test('zero survivors is the error state, not an empty menu', () {
      expect(code.contains('if (ideas.isEmpty)'), isTrue);
      expect(code.contains("avoid your allergens"), isTrue);
    });
  });

  group('4d — every drop is logged', () {
    test('to the same log recipes use', () {
      expect(code.contains('AllergenFlagLog.record'), isTrue);
      final recipes = File('lib/services/validated_recipe_generation.dart')
          .readAsStringSync();
      expect(recipes.contains('AllergenFlagLog.record'), isTrue,
          reason: 'one log for both, so the rate is one number');
    });
  });
}
