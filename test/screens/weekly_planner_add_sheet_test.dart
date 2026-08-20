import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/models/cook_mode_recipe_codec.dart';
import 'package:optimeal/models/recipe_origin.dart';
import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/weekly_planner_screen.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/services/saved_recipes_service.dart';
import 'package:optimeal/widgets/recipe_provenance_badges.dart';

import '../support/fake_saved_recipes_backend.dart';

class _StubScreen extends StatelessWidget {
  const _StubScreen(this.label);
  final String label;
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}

Widget _wrap(SavedRecipesService service) {
  final router = GoRouter(
    initialLocation: AppRoutes.weeklyPlan,
    routes: [
      GoRoute(
        path: AppRoutes.weeklyPlan,
        builder: (context, state) =>
            WeeklyPlannerScreen(savedRecipesService: service),
      ),
      GoRoute(
          path: AppRoutes.home, builder: (c, s) => const _StubScreen('home')),
      GoRoute(
          path: AppRoutes.fridgeClearerPicker,
          builder: (c, s) => const _StubScreen('fridge picker')),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

SavedRecipesService _service(FakeSavedRecipesBackend backend) =>
    SavedRecipesService(
      backend: backend,
      sessionStorage: CookSessionStorageService(),
    );

/// Opens the planner's add-meal sheet from the first empty slot.
Future<void> _openAddSheet(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('+ Add Meal').first);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('three sources', () {
    testWidgets('the add sheet offers all three sources', (tester) async {
      await tester.pumpWidget(_wrap(_service(FakeSavedRecipesBackend())));
      await _openAddSheet(tester);

      expect(find.text('Clear Fridge Leftovers'), findsOneWidget);
      expect(find.text('Custom AI Craving'), findsOneWidget);
      expect(find.text('My recipes'), findsOneWidget);
    });

    testWidgets('the sheet has an X in addition to drag-down and barrier tap',
        (tester) async {
      await tester.pumpWidget(_wrap(_service(FakeSavedRecipesBackend())));
      await _openAddSheet(tester);

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Clear Fridge Leftovers'), findsNothing);
    });
  });

  group('pane swap', () {
    testWidgets('My recipes swaps the pane in place — never a second sheet',
        (tester) async {
      final service = _service(FakeSavedRecipesBackend());
      await service.save(testRecipe('Saved Dish'));

      await tester.pumpWidget(_wrap(service));
      await _openAddSheet(tester);

      final sheetsBefore = find.byType(BottomSheet).evaluate().length;

      await tester.tap(find.text('My recipes'));
      await tester.pumpAndSettle();

      expect(find.text('Clear Fridge Leftovers'), findsNothing,
          reason: 'the sources pane is replaced, not covered');
      expect(find.text('Saved Dish'), findsOneWidget);
      expect(find.byType(BottomSheet).evaluate().length, sheetsBefore,
          reason: 'sheets never stack');
    });

    testWidgets('the back arrow returns to the three sources', (tester) async {
      final service = _service(FakeSavedRecipesBackend());
      await service.save(testRecipe('Saved Dish'));

      await tester.pumpWidget(_wrap(service));
      await _openAddSheet(tester);
      await tester.tap(find.text('My recipes'));
      await tester.pumpAndSettle();

      // By tooltip, not by icon: the planner's own app-bar back button uses
      // the same glyph.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Clear Fridge Leftovers'), findsOneWidget);
      expect(find.text('Custom AI Craving'), findsOneWidget);
      expect(find.text('Saved Dish'), findsNothing);
    });

    testWidgets(
        'the picker pane shows the leaf badge on Fridge Clearer rows only',
        (tester) async {
      final service = _service(FakeSavedRecipesBackend());
      await service
          .save(testRecipe('Rescue Dish', origin: RecipeOrigin.fridgeClearer));
      await service.save(testRecipe('Craving Dish',
          origin: RecipeOrigin.customAiRecipeCreator));

      await tester.pumpWidget(_wrap(service));
      await _openAddSheet(tester);
      await tester.tap(find.text('My recipes'));
      await tester.pumpAndSettle();

      expect(find.text('Rescue Dish'), findsOneWidget);
      expect(find.text('Craving Dish'), findsOneWidget);
      expect(find.byType(ProvenanceLeafBadge), findsOneWidget);
    });

    testWidgets('an empty shelf shows a message, not an empty pane',
        (tester) async {
      await tester.pumpWidget(_wrap(_service(FakeSavedRecipesBackend())));
      await _openAddSheet(tester);
      await tester.tap(find.text('My recipes'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing saved yet'), findsOneWidget);
    });
  });

  group('placement', () {
    testWidgets(
        'tapping a saved recipe places it into the day and closes the sheet',
        (tester) async {
      final service = _service(FakeSavedRecipesBackend());
      await service.save(testRecipe('Place Me'));

      await tester.pumpWidget(_wrap(service));
      await _openAddSheet(tester);
      await tester.tap(find.text('My recipes'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Place Me'));
      await tester.pumpAndSettle();

      // Sheet gone, meal in the day, marked as coming from the shelf.
      expect(find.text('My recipes'), findsNothing);
      expect(find.text('Place Me'), findsOneWidget);
      expect(find.byType(FromSavedChip), findsOneWidget);
    });

    testWidgets('a placed Fridge Clearer recipe keeps its leaf badge',
        (tester) async {
      final service = _service(FakeSavedRecipesBackend());
      await service
          .save(testRecipe('Rescue Dish', origin: RecipeOrigin.fridgeClearer));

      await tester.pumpWidget(_wrap(service));
      await _openAddSheet(tester);
      await tester.tap(find.text('My recipes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rescue Dish'));
      await tester.pumpAndSettle();

      // Both: the leaf comes from the recipe's own provenance, the chip from
      // how it got into this day.
      expect(find.byType(ProvenanceLeafBadge), findsOneWidget);
      expect(find.byType(FromSavedChip), findsOneWidget);
    });
  });

  group('provenance survives placement', () {
    test(
        'a saved Fridge Clearer recipe round-trips through recipe_payload with '
        'origin and entered ingredients intact', () {
      // This is the hop that decides whether a planner-cooked rescue counts:
      // saved payload -> user_meal_plans.recipe_payload jsonb -> back out.
      final original = testRecipe('Rescue Dish',
          origin: RecipeOrigin.fridgeClearer, entered: ['Zucchini', 'Feta']);

      final stored = jsonDecode(jsonEncode(cookModeRecipeToJson(original)));
      final decoded = cookModeRecipeFromJson(stored)!;

      expect(decoded.origin, RecipeOrigin.fridgeClearer);
      expect(decoded.origin!.isRescueEligible, isTrue);
      expect(decoded.originEnteredIngredients, ['Zucchini', 'Feta']);
    });

    test('a placed custom craving stays non-rescue after the same round trip',
        () {
      final original = testRecipe('Craving Dish',
          origin: RecipeOrigin.customAiRecipeCreator);
      final stored = jsonDecode(jsonEncode(cookModeRecipeToJson(original)));
      final decoded = cookModeRecipeFromJson(stored)!;

      expect(decoded.origin, RecipeOrigin.customAiRecipeCreator);
      expect(decoded.origin!.isRescueEligible, isFalse);
    });

    testWidgets('the placed meal carries the full payload, not just a title',
        (tester) async {
      final service = _service(FakeSavedRecipesBackend());
      final saved = testRecipe('Rescue Dish',
          origin: RecipeOrigin.fridgeClearer, entered: ['Zucchini']);
      await service.save(saved);

      await tester.pumpWidget(_wrap(service));
      await _openAddSheet(tester);
      await tester.tap(find.text('My recipes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rescue Dish'));
      await tester.pumpAndSettle();

      // The row is tappable into Cook Mode, which is only true when a real
      // CookModeRecipePayload came through — a title-only placement renders
      // the "missing Cook Mode steps" path instead.
      await tester.tap(find.text('Rescue Dish'));
      await tester.pumpAndSettle();
      expect(find.text('This meal is missing Cook Mode steps.'), findsNothing);
    });
  });
}
