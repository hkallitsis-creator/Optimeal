import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/services/chef_recipe_parser.dart';

void main() {
  group('parseChefRecipeJson', () {
    const validRaw = '''
    {
      "title": "Braised Chicken and Cabbage",
      "description": "A cozy one-pan braise.",
      "ingredients": [
        {"name": "Chicken thigh", "amount": 2, "unit": "piece"},
        {"name": "Cabbage", "amount": 300, "unit": "g"}
      ],
      "kitchen_gear": ["1 Pan or Pot", "Tongs"],
      "steps": [
        {
          "title": "Sear the chicken",
          "duration_minutes": 6,
          "heat": "medium_high",
          "bullets": ["Skin-side down, don't move it."]
        },
        {
          "title": "Add cabbage and braise",
          "duration_minutes": 15,
          "heat": "medium",
          "bullets": ["Cover and let it go until tender."]
        }
      ],
      "curriculum_lesson_ids": ["braising", "pan_searing"]
    }
    ''';

    test('valid JSON parses every field correctly', () async {
      final result = await parseChefRecipeJson(
        raw: validRaw,
        portions: 3,
        fallbackTitle: 'Fallback Title',
        surface: ChefRecipeSurface.fridgeClearer,
        readDescription: true,
      );

      expect(result, isNotNull);
      expect(result!.title, 'Braised Chicken and Cabbage');
      expect(result.description, 'A cozy one-pan braise.');
      expect(result.ingredients, ['2 piece Chicken thigh', '300 g Cabbage']);
      expect(result.kitchenGear, ['1 Pan or Pot', 'Tongs']);
      expect(result.steps, hasLength(2));
      expect(result.steps[0].title, 'Sear the chicken');
      expect(result.steps[0].heat, 'medium_high');
      expect(result.steps[0].durationMinutes, 6);
      expect(result.steps[0].bullets, ["Skin-side down, don't move it."]);
      expect(result.structuredIngredients, isNotNull);
      expect(result.structuredIngredients, hasLength(2));
      expect(result.structuredIngredients![0].name, 'Chicken thigh');
      expect(result.structuredIngredients![0].amount, 2);
      expect(result.structuredIngredients![0].unit, 'piece');
      expect(result.basePortions, 3);
      expect(result.curriculumLessonIds, ['braising', 'pan_searing']);
    });

    test('non-JSON text returns null', () async {
      final result = await parseChefRecipeJson(
        raw: "Sorry, I can't help with that right now. Happy cooking! — Chef Harris",
        portions: 2,
        fallbackTitle: 'Fallback',
        surface: ChefRecipeSurface.fridgeClearer,
      );
      expect(result, isNull);
    });

    test('JSON that decodes but is not an object returns null', () async {
      final result = await parseChefRecipeJson(
        raw: '[1, 2, 3]',
        portions: 2,
        fallbackTitle: 'Fallback',
        surface: ChefRecipeSurface.fridgeClearer,
      );
      expect(result, isNull);
    });

    test('empty steps array returns null', () async {
      const raw = '{"title": "Empty Steps", "ingredients": [], "kitchen_gear": [], "steps": []}';
      final result = await parseChefRecipeJson(
        raw: raw,
        portions: 2,
        fallbackTitle: 'Fallback',
        surface: ChefRecipeSurface.fridgeClearer,
      );
      expect(result, isNull);
    });

    const noIngredientsRaw = '''
    {
      "title": "No Ingredients Listed",
      "kitchen_gear": ["Pan"],
      "steps": [{"title": "Cook", "duration_minutes": 5, "heat": "medium", "bullets": ["Go"]}]
    }
    ''';

    test('missing ingredients + useGenericFallbacks true substitutes the default list', () async {
      final result = await parseChefRecipeJson(
        raw: noIngredientsRaw,
        portions: 2,
        fallbackTitle: 'Fallback',
        surface: ChefRecipeSurface.customAiRecipeCreator,
        useGenericFallbacks: true,
      );
      expect(result, isNotNull);
      expect(result!.ingredients, ['Salt', 'Pepper', 'Cooking oil']);
      expect(result.structuredIngredients, isNull);
    });

    test('missing ingredients + useGenericFallbacks false stays empty', () async {
      final result = await parseChefRecipeJson(
        raw: noIngredientsRaw,
        portions: 2,
        fallbackTitle: 'Fallback',
        surface: ChefRecipeSurface.fridgeClearer,
        useGenericFallbacks: false,
      );
      expect(result, isNotNull);
      expect(result!.ingredients, isEmpty);
    });

    const noGearRaw = '''
    {
      "title": "No Gear Listed",
      "ingredients": [{"name": "Egg", "amount": 2, "unit": "piece"}],
      "steps": [{"title": "Cook", "duration_minutes": 5, "heat": "medium", "bullets": ["Go"]}]
    }
    ''';

    test('missing kitchen_gear + useGenericFallbacks true substitutes the default list', () async {
      final result = await parseChefRecipeJson(
        raw: noGearRaw,
        portions: 2,
        fallbackTitle: 'Fallback',
        surface: ChefRecipeSurface.fridgeCountdown,
        useGenericFallbacks: true,
      );
      expect(result, isNotNull);
      expect(result!.kitchenGear, ['1 Pan or Pot', 'Knife', 'Spoon/Spatula']);
    });

    test('missing kitchen_gear + useGenericFallbacks false stays empty', () async {
      final result = await parseChefRecipeJson(
        raw: noGearRaw,
        portions: 2,
        fallbackTitle: 'Fallback',
        surface: ChefRecipeSurface.fridgeClearer,
        useGenericFallbacks: false,
      );
      expect(result, isNotNull);
      expect(result!.kitchenGear, isEmpty);
    });

    test('missing title falls back to fallbackTitle', () async {
      const raw = '''
      {
        "ingredients": [{"name": "Egg", "amount": 2, "unit": "piece"}],
        "kitchen_gear": ["Pan"],
        "steps": [{"title": "Cook", "duration_minutes": 5, "heat": "medium", "bullets": ["Go"]}]
      }
      ''';
      final result = await parseChefRecipeJson(
        raw: raw,
        portions: 2,
        fallbackTitle: 'Use it tonight',
        surface: ChefRecipeSurface.fridgeCountdown,
      );
      expect(result, isNotNull);
      expect(result!.title, 'Use it tonight');
    });

    const withDescriptionRaw = '''
    {
      "title": "Has Description",
      "description": "Rescuing this just in time.",
      "ingredients": [{"name": "Egg", "amount": 2, "unit": "piece"}],
      "kitchen_gear": ["Pan"],
      "steps": [{"title": "Cook", "duration_minutes": 5, "heat": "medium", "bullets": ["Go"]}]
    }
    ''';

    test('readDescription true captures the description field', () async {
      final result = await parseChefRecipeJson(
        raw: withDescriptionRaw,
        portions: 2,
        fallbackTitle: 'Fallback',
        surface: ChefRecipeSurface.fridgeClearer,
        readDescription: true,
      );
      expect(result, isNotNull);
      expect(result!.description, 'Rescuing this just in time.');
    });

    test('readDescription false (default) discards the description field even when present', () async {
      final result = await parseChefRecipeJson(
        raw: withDescriptionRaw,
        portions: 2,
        fallbackTitle: 'Fallback',
        surface: ChefRecipeSurface.fridgeCountdown,
        readDescription: false,
      );
      expect(result, isNotNull);
      expect(result!.description, isNull);
    });
  });
}
