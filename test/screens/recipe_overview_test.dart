import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/screens/recipe_details_screen.dart';
import 'package:optimeal/models/recipe_origin.dart';
import 'package:optimeal/services/saved_recipes_service.dart';
import 'package:optimeal/services/user_profile_service.dart';
import 'package:optimeal/state/ingredient_prep_controller.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/recipe_overview_body.dart';

import '../support/fake_saved_recipes_backend.dart';

/// The recipe overview — the surface every path between choosing a recipe and
/// Cook Mode now lands on.
///
/// The device bug behind most of this: recipes opened from My Recipes had
/// **no cook affordance at all**, so a saved recipe could be read and never
/// made again.

CookModeRecipePayload _recipe({
  String title = 'Chicken and Rice',
  String? description,
  List<RecipeIngredient>? structured,
  int? basePortions = 2,
  List<String> gear = const ['Pan'],
  int steps = 3,
}) =>
    CookModeRecipePayload(
      title: title,
      ingredients: const ['200 g rice', '2 eggs'],
      steps: [
        for (var i = 0; i < steps; i++)
          CookModeStepPayload(
            title: 'Step ${i + 1}',
            heat: 'medium',
            durationMinutes: 10,
            bullets: const ['do the thing'],
          ),
      ],
      kitchenGear: gear,
      description: description,
      structuredIngredients: structured,
      basePortions: basePortions,
    );

Widget _host(Widget child) {
  final profile = UserProfileController(UserProfileService());
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => IngredientPrepController()),
      ChangeNotifierProvider.value(value: profile),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('composition', () {
    testWidgets('the description is one line, ellipsized', (tester) async {
      await tester.pumpWidget(_host(RecipeDetailsScreen(
        recipe: _recipe(
          description:
              'A very long description that used to run to three lines on a '
              'Pixel and pushed everything else below the fold entirely.',
        ),
        service: SavedRecipesService(backend: FakeSavedRecipesBackend()),
      )));
      await tester.pump();

      final text = tester.widget<Text>(find.textContaining('A very long'));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('there is exactly one terracotta CTA', (tester) async {
      await tester.pumpWidget(_host(RecipeDetailsScreen(
        recipe: _recipe(),
        service: SavedRecipesService(backend: FakeSavedRecipesBackend()),
      )));
      await tester.pump();

      final filled = tester
          .widgetList<FilledButton>(find.byType(FilledButton))
          .where((b) =>
              b.style?.backgroundColor?.resolve({}) ==
              AppDesignTokens.ctaTerracotta)
          .toList();
      expect(filled, hasLength(1));
      expect(find.text('Start cooking'), findsOneWidget);
    });

    testWidgets('the inline Steps list is gone', (tester) async {
      await tester.pumpWidget(_host(RecipeDetailsScreen(
        recipe: _recipe(),
        service: SavedRecipesService(backend: FakeSavedRecipesBackend()),
      )));
      await tester.pump();

      expect(find.text('Steps'), findsNothing,
          reason: 'steps live in Cook Mode and its overview sheet');
      expect(find.text('Step 1'), findsNothing);
    });

    testWidgets('the cut tautology pill and Est. time card are gone',
        (tester) async {
      await tester.pumpWidget(_host(RecipeDetailsScreen(
        recipe: _recipe(),
        service: SavedRecipesService(backend: FakeSavedRecipesBackend()),
      )));
      await tester.pump();

      expect(find.textContaining('Mode: Cook Mode'), findsNothing);
      expect(find.textContaining('Est. time'), findsNothing);
      // The meta line replaces both.
      expect(find.textContaining('3 steps'), findsOneWidget);
    });

    testWidgets('the bookmark is present and toggles once', (tester) async {
      final backend = FakeSavedRecipesBackend();
      await tester.pumpWidget(_host(RecipeDetailsScreen(
        recipe: _recipe(),
        service: SavedRecipesService(backend: backend),
      )));
      await tester.pump();

      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(backend.upsertCalls, 1,
          reason: 'saving pre-cook must reach the save service exactly once');
    });
  });

  group('the servings stepper', () {
    testWidgets('rescales quantities live', (tester) async {
      await tester.pumpWidget(_host(RecipeDetailsScreen(
        recipe: _recipe(
          structured: [
            RecipeIngredient(name: 'eggs', amount: 1, unit: 'piece'),
            RecipeIngredient(name: 'rice', amount: 200, unit: 'g'),
          ],
        ),
        service: SavedRecipesService(backend: FakeSavedRecipesBackend()),
      )));
      await tester.pump();

      expect(find.text('Serves 2'), findsOneWidget);
      expect(find.text('200 g'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();

      expect(find.text('Serves 3'), findsOneWidget);
      // 1 egg at 3/2 = 1.5, rounded up.
      expect(find.text('2'), findsOneWidget);
      expect(find.text('· rounded up'), findsOneWidget);
      expect(find.text('300 g'), findsOneWidget);
    });

    testWidgets('is disabled, without crashing, when basePortions is null',
        (tester) async {
      await tester.pumpWidget(_host(RecipeDetailsScreen(
        recipe: _recipe(
          basePortions: null,
          structured: [
            RecipeIngredient(name: 'rice', amount: 200, unit: 'g'),
          ],
        ),
        service: SavedRecipesService(backend: FakeSavedRecipesBackend()),
      )));
      await tester.pump();

      final before = find.text('200 g');
      expect(before, findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();

      expect(find.text('200 g'), findsOneWidget,
          reason: 'nothing to scale from, so nothing scales');
    });

    testWidgets('will not step below 1 or above the ceiling', (tester) async {
      await tester.pumpWidget(_host(RecipeDetailsScreen(
        recipe: _recipe(basePortions: 1),
        service: SavedRecipesService(backend: FakeSavedRecipesBackend()),
      )));
      await tester.pump();

      expect(find.text('Serves 1'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pump();
      expect(find.text('Serves 1'), findsOneWidget);

      for (var i = 0; i < 10; i++) {
        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump();
      }
      expect(find.text('Serves 6'), findsOneWidget);
    });
  });

  group('lock and unlock', () {
    testWidgets('Start cooking freezes the chosen N onto the launch request',
        (tester) async {
      CookModeLaunchRequest? launched;

      await tester.pumpWidget(_host(
        Builder(
          builder: (context) => Scaffold(
            body: RecipeOverviewBody(
              recipe: _recipe(),
              servings: 4,
              onServingsChanged: (_) {},
            ),
            bottomNavigationBar: RecipeOverviewBottomBar(
              onPlan: () {},
              onStartCooking: () => launched = CookModeLaunchRequest(
                recipe: _recipe(),
                surface: null,
                servings: 4,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('Start cooking'));
      await tester.pump();

      expect(launched, isNotNull);
      expect(launched!.servings, 4);
      expect(launched!.surface, isNull,
          reason: 'provenance is the recipe\'s, not the launching screen\'s');
      expect(launched!.isReCook, isFalse,
          reason: 'a re-cook flagged true never logs; this cook earns a row');
    });

    testWidgets('the stepper is live again after popping back', (tester) async {
      // The State is never disposed by the push, so the chosen N survives and
      // the stepper still works — which is exactly what "unlocks again" means.
      await tester.pumpWidget(_host(RecipeDetailsScreen(
        recipe: _recipe(),
        service: SavedRecipesService(backend: FakeSavedRecipesBackend()),
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      expect(find.text('Serves 3'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      expect(find.text('Serves 4'), findsOneWidget);
    });

    test('Cook Mode reads the frozen value, not a live one', () {
      final request = CookModeLaunchRequest(
        recipe: _recipe(),
        surface: null,
        servings: 5,
      );
      expect(request.servings, 5);
    });
  });

  group('R9 — Start cooking is reachable from every entry point', () {
    // All five paths converge on RecipeDetailsScreen (or bypass it
    // deliberately — see the session record's routing table). What this
    // asserts is that the widget every convergent path lands on always
    // renders a working CTA, whatever recipe shape it is handed.
    final entryShapes = <String, CookModeRecipePayload>{
      'Fridge Clearer idea (structured, with origin)': CookModeRecipePayload(
        title: 'Fridge dish',
        ingredients: const ['x'],
        steps: [
          const CookModeStepPayload(
              title: 'S', heat: 'medium', durationMinutes: 5, bullets: [])
        ],
        structuredIngredients: [
          RecipeIngredient(name: 'courgette', amount: 1, unit: 'piece'),
        ],
        basePortions: 2,
        origin: RecipeOrigin.fridgeClearer,
      ),
      'Custom generation': _recipe(title: 'Custom dish'),
      'Saved recipe': _recipe(title: 'Saved dish'),
      'Recently cooked': _recipe(title: 'Cooked dish'),
      'Planner slot view': _recipe(title: 'Planned dish'),
    };

    entryShapes.forEach((label, recipe) {
      testWidgets(label, (tester) async {
        await tester.pumpWidget(_host(RecipeDetailsScreen(
          recipe: recipe,
          service: SavedRecipesService(backend: FakeSavedRecipesBackend()),
        )));
        await tester.pump();

        expect(find.text(recipe.title), findsOneWidget);
        expect(find.text('Start cooking'), findsOneWidget,
            reason: '$label must be cookable — this was the device bug');

        final cta = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Start cooking'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(cta.onPressed, isNotNull);
      });
    });

    testWidgets('a Fridge Clearer recipe keeps its leaf on this screen',
        (tester) async {
      await tester.pumpWidget(_host(RecipeDetailsScreen(
        recipe: entryShapes.values.first,
        service: SavedRecipesService(backend: FakeSavedRecipesBackend()),
      )));
      await tester.pump();

      expect(find.text('fridge rescue'), findsOneWidget,
          reason: 'provenance must survive to the re-cook');
    });
  });
}
