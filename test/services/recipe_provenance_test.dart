import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/models/cook_mode_recipe_codec.dart';
import 'package:optimeal/models/recipe_origin.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/chef_recipe_parser.dart';
import 'package:optimeal/services/ledger_service.dart';
import 'package:optimeal/services/ledger_verdict.dart';

/// The signed provenance rule: Fridge Clearer rescue eligibility travels
/// WITH THE RECIPE, not with the screen that launched a given cook.
///
/// The bug these tests lock down: a Fridge Clearer recipe scheduled into the
/// Weekly Planner and cooked from there used to be judged by launch surface
/// (`CookModeSurface.weeklyPlanner`, not rescue-eligible) and so did not
/// count, even though the food really was rescued from the user's fridge.

const String _fridgeClearerJson = '''
{
  "title": "Zucchini and Feta Skillet",
  "ingredients": [{"name": "Zucchini", "amount": 300, "unit": "g"},
                  {"name": "Feta", "amount": 100, "unit": "g"},
                  {"name": "Olive oil", "amount": 1, "unit": "tbsp"}],
  "steps": [{"title": "Sear the zucchini", "heat": "medium_high",
             "duration_minutes": 6, "bullets": ["Cut into coins.", "Sear without crowding."]}]
}
''';

const String _customCravingJson = '''
{
  "title": "Weeknight Carbonara",
  "ingredients": [{"name": "Spaghetti", "amount": 200, "unit": "g"},
                  {"name": "Pancetta", "amount": 80, "unit": "g"}],
  "steps": [{"title": "Boil and toss", "heat": "medium",
             "duration_minutes": 10, "bullets": ["Salt the water.", "Toss off heat."]}]
}
''';

/// The ingredients the user typed into Fridge Clearer for the generation
/// above. In the app this is attached by `FridgeClearerScreen` right after
/// parsing; here it is applied the same way, through `copyWith`.
const List<String> _enteredIngredients = ['Zucchini', 'Feta'];

Future<CookModeRecipePayload> _generateFridgeClearerRecipe() async {
  final parsed = await parseChefRecipeJson(
    raw: _fridgeClearerJson,
    portions: 2,
    fallbackTitle: 'Fridge Clearer Recipe',
    surface: ChefRecipeSurface.fridgeClearer,
    useGenericFallbacks: false,
    readDescription: true,
  );
  return parsed!.copyWith(originEnteredIngredients: _enteredIngredients);
}

Future<CookModeRecipePayload> _generateCustomCravingRecipe() async {
  final parsed = await parseChefRecipeJson(
    raw: _customCravingJson,
    portions: 2,
    fallbackTitle: 'Custom Recipe',
    surface: ChefRecipeSurface.customAiRecipeCreator,
  );
  return parsed!;
}

/// Exactly what the Weekly Planner does to a recipe: encode it into
/// `user_meal_plans.recipe_payload` jsonb, and decode it back out days later.
/// jsonEncode/jsonDecode is in here on purpose — this is the hop the
/// provenance fields have to survive.
CookModeRecipePayload _throughPlannerJsonb(CookModeRecipePayload recipe) {
  final stored = jsonDecode(jsonEncode(cookModeRecipeToJson(recipe)));
  return cookModeRecipeFromJson(stored)!;
}

/// The eligibility decision, as `_logCookSessionCompletion` now makes it.
/// Deliberately takes the launch surface as well, so a test can prove the
/// surface is genuinely ignored rather than merely absent.
bool _isRescueEligibleCook(
  CookModeRecipePayload recipe, {
  required CookModeSurface launchedFrom,
  bool isReCook = false,
}) {
  return (recipe.origin?.isRescueEligible ?? false) && !isReCook;
}

void main() {
  group('provenance is stamped at generation', () {
    test('a Fridge Clearer generation carries origin + entered ingredients',
        () async {
      final recipe = await _generateFridgeClearerRecipe();
      expect(recipe.origin, RecipeOrigin.fridgeClearer);
      expect(recipe.originEnteredIngredients, _enteredIngredients);
    });

    test('a Custom AI Recipe Creator generation carries a non-rescue origin',
        () async {
      final recipe = await _generateCustomCravingRecipe();
      expect(recipe.origin, RecipeOrigin.customAiRecipeCreator);
      expect(recipe.origin!.isRescueEligible, isFalse);
      expect(recipe.originEnteredIngredients, isNull);
    });
  });

  group('(a) Fridge Clearer recipe cooked directly', () {
    test('counts as a rescue', () async {
      final recipe = await _generateFridgeClearerRecipe();

      expect(
        _isRescueEligibleCook(recipe,
            launchedFrom: CookModeSurface.fridgeClearer),
        isTrue,
      );
      expect(
        selectLedgerVerdict(
          hasPayload: true,
          isReCook: false,
          origin: recipe.origin,
          result: const LedgerCompletionSuccess(
              ingredientsRescued: 2,
              ingredientsRescuedList: ['Zucchini', 'Feta'],
              lifetimeIngredientsRescued: 2),
        ),
        LedgerVerdict.counted,
      );
      expect(recipe.origin!.ledgerSourceValue, 'fridge_clearer');
    });

    test('credits the ingredients the user actually entered', () async {
      final recipe = await _generateFridgeClearerRecipe();
      expect(
        LedgerService.computeRescuedIngredients(
          enteredIngredients: recipe.originEnteredIngredients!,
          cookedIngredients: recipe.ingredients,
        ),
        ['Zucchini', 'Feta'],
      );
    });
  });

  group('(b) same recipe scheduled to the planner, cooked from the planner',
      () {
    test('survives the recipe_payload jsonb round trip with provenance intact',
        () async {
      final planned =
          _throughPlannerJsonb(await _generateFridgeClearerRecipe());
      expect(planned.origin, RecipeOrigin.fridgeClearer);
      expect(planned.originEnteredIngredients, _enteredIngredients);
    });

    test('still counts as a rescue — this is the bug being fixed', () async {
      final planned =
          _throughPlannerJsonb(await _generateFridgeClearerRecipe());

      expect(
        _isRescueEligibleCook(planned,
            launchedFrom: CookModeSurface.weeklyPlanner),
        isTrue,
        reason: 'a planner-launched cook of a Fridge Clearer recipe must count',
      );
      expect(
        selectLedgerVerdict(
          hasPayload: true,
          isReCook: false,
          origin: planned.origin,
          result: const LedgerCompletionSuccess(
              ingredientsRescued: 2,
              ingredientsRescuedList: ['Zucchini', 'Feta'],
              lifetimeIngredientsRescued: 2),
        ),
        LedgerVerdict.counted,
      );
    });

    test('credits the same ingredients as the direct cook', () async {
      final direct = await _generateFridgeClearerRecipe();
      final planned = _throughPlannerJsonb(direct);

      final directCredit = LedgerService.computeRescuedIngredients(
        enteredIngredients: direct.originEnteredIngredients!,
        cookedIngredients: direct.ingredients,
      );
      final plannedCredit = LedgerService.computeRescuedIngredients(
        enteredIngredients: planned.originEnteredIngredients!,
        cookedIngredients: planned.ingredients,
      );

      expect(plannedCredit, directCredit);
      expect(plannedCredit, isNotEmpty);
    });

    test('a re-cook from the planner still does not count twice', () async {
      final planned =
          _throughPlannerJsonb(await _generateFridgeClearerRecipe());
      expect(
        _isRescueEligibleCook(planned,
            launchedFrom: CookModeSurface.weeklyPlanner, isReCook: true),
        isFalse,
      );
      expect(
        selectLedgerVerdict(
            hasPayload: true,
            isReCook: true,
            origin: planned.origin,
            result: null),
        LedgerVerdict.notCountedReCook,
      );
    });
  });

  group('(c) a custom recipe cooked from anywhere', () {
    test('does not count, from any launch surface', () async {
      final recipe = await _generateCustomCravingRecipe();
      for (final surface in CookModeSurface.values) {
        expect(
          _isRescueEligibleCook(recipe, launchedFrom: surface),
          isFalse,
          reason: 'a custom craving launched from $surface must not count',
        );
      }
      expect(
        selectLedgerVerdict(
            hasPayload: true,
            isReCook: false,
            origin: recipe.origin,
            result: null),
        LedgerVerdict.notCountedNotFridgeRecipe,
      );
    });

    test('does not count after a planner round trip either', () async {
      final planned =
          _throughPlannerJsonb(await _generateCustomCravingRecipe());
      expect(planned.origin, RecipeOrigin.customAiRecipeCreator);
      expect(
        _isRescueEligibleCook(planned,
            launchedFrom: CookModeSurface.weeklyPlanner),
        isFalse,
      );
    });
  });

  group('legacy payloads', () {
    test(
        'a payload stored before provenance existed decodes to no origin and does not count',
        () {
      // A recipe_payload row written by an older build: same shape, minus the
      // two provenance keys.
      final legacy = <String, dynamic>{
        'title': 'Old Planned Meal',
        'ingredients': ['300g Zucchini'],
        'steps': [
          {
            'title': 'Cook it',
            'heat': 'medium',
            'duration_minutes': 5,
            'bullets': ['Go.']
          }
        ],
      };
      final decoded = cookModeRecipeFromJson(legacy)!;

      expect(decoded.origin, isNull);
      expect(decoded.originEnteredIngredients, isNull);
      expect(
        _isRescueEligibleCook(decoded,
            launchedFrom: CookModeSurface.fridgeClearer),
        isFalse,
        reason:
            'unknown provenance must degrade to not-eligible, never be guessed',
      );
    });

    test('an unrecognized origin name decodes to null rather than throwing',
        () {
      expect(RecipeOrigin.fromName('some_future_origin'), isNull);
      expect(RecipeOrigin.fromName(null), isNull);
      expect(RecipeOrigin.fromName(''), isNull);
      expect(
          RecipeOrigin.fromName('fridgeClearer'), RecipeOrigin.fridgeClearer);
    });
  });
}
