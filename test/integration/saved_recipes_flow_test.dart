import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/models/cook_mode_recipe_codec.dart';
import 'package:optimeal/models/recipe_origin.dart';
import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/home_dashboard_screen.dart';
import 'package:optimeal/screens/my_recipes_screen.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/screens/weekly_planner_screen.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/services/ledger_service.dart';
import 'package:optimeal/services/ledger_verdict.dart';
import 'package:optimeal/services/saved_recipes_service.dart';
import 'package:optimeal/services/user_profile_service.dart';
import 'package:optimeal/services/weekly_planner_intent_service.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/widgets/recipe_provenance_badges.dart';

import '../support/fake_saved_recipes_backend.dart';

/// Cross-build integration checks. Each build shipped tests for its own
/// surfaces; these cover the SEAMS between them, which is where nothing was
/// looking.

/// The text scales Home is verified to render without overflowing. See the
/// note in the accessibility group for the measured breaking point.
const List<double> kHomeSupportedTextScales = <double>[1.0, 1.3, 1.6, 2.0, 2.4];

class _StubScreen extends StatelessWidget {
  const _StubScreen(this.label);
  final String label;
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}

SavedRecipesService _service(FakeSavedRecipesBackend backend) =>
    SavedRecipesService(
      backend: backend,
      sessionStorage: CookSessionStorageService(),
    );

/// Router carrying the three screens the flow crosses.
Widget _wrapApp(SavedRecipesService service) {
  final router = GoRouter(
    initialLocation: AppRoutes.myRecipes,
    observers: [routeObserver],
    routes: [
      GoRoute(
        path: AppRoutes.myRecipes,
        builder: (c, s) => MyRecipesScreen(service: service),
      ),
      GoRoute(
        path: AppRoutes.weeklyPlan,
        builder: (c, s) => WeeklyPlannerScreen(savedRecipesService: service),
      ),
      GoRoute(
          path: AppRoutes.home, builder: (c, s) => const _StubScreen('home')),
      GoRoute(
        path: AppRoutes.recipe,
        builder: (c, s) => const _StubScreen('details'),
      ),
    ],
  );
  return ChangeNotifierProvider<UserProfileController>.value(
    value: UserProfileController(UserProfileService()),
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The planner intent service is a singleton; a leftover intent from a
    // previous test would bleed across.
    WeeklyPlannerIntentService.instance.consumePending();
  });

  group('seam: My recipes calendar action -> Weekly Planner day', () {
    testWidgets(
        'scheduling a saved Fridge Clearer recipe lands it in the planner with '
        'BOTH the leaf badge and the from-saved chip', (tester) async {
      final service = _service(FakeSavedRecipesBackend());
      await service.save(testRecipe('Rescue Dish',
          origin: RecipeOrigin.fridgeClearer, entered: ['Zucchini']));

      await tester.pumpWidget(_wrapApp(service));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.calendar_month_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wednesday'));
      await tester.pumpAndSettle();

      // Landed on the planner, on the chosen day, with provenance intact.
      expect(find.text('Rescue Dish'), findsOneWidget);
      expect(find.byType(ProvenanceLeafBadge), findsOneWidget,
          reason: 'leaf comes from the recipe payload, through the intent');
      expect(find.byType(FromSavedChip), findsOneWidget,
          reason: 'chip comes from kFromSavedMealSource on the intent');
    });

    testWidgets('a saved custom craving gets the chip but NOT the leaf',
        (tester) async {
      final service = _service(FakeSavedRecipesBackend());
      await service.save(testRecipe('Craving Dish',
          origin: RecipeOrigin.customAiRecipeCreator));

      await tester.pumpWidget(_wrapApp(service));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.calendar_month_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Monday'));
      await tester.pumpAndSettle();

      expect(find.byType(FromSavedChip), findsOneWidget);
      expect(find.byType(ProvenanceLeafBadge), findsNothing);
    });
  });

  group('seam: provenance survives BOTH jsonb hops', () {
    test(
        'Fridge Clearer -> saved_recipes.recipe_payload -> '
        'user_meal_plans.recipe_payload -> still a counted rescue', () {
      final generated = testRecipe('Rescue Dish',
          origin: RecipeOrigin.fridgeClearer, entered: ['Zucchini', 'Feta']);

      // Hop 1: saved_recipes.recipe_payload (SavedRecipesService._rowFor).
      final savedRow = jsonDecode(jsonEncode(cookModeRecipeToJson(generated)));
      final fromSaved = cookModeRecipeFromJson(savedRow)!;

      // Hop 2: user_meal_plans.recipe_payload (the planner's row mapping).
      final plannedRow =
          jsonDecode(jsonEncode(cookModeRecipeToJson(fromSaved)));
      final fromPlanner = cookModeRecipeFromJson(plannedRow)!;

      expect(fromPlanner.origin, RecipeOrigin.fridgeClearer);
      expect(fromPlanner.originEnteredIngredients, ['Zucchini', 'Feta']);

      // What _logCookSessionCompletion then does with it.
      expect(
        selectLedgerVerdict(
          hasPayload: true,
          isReCook: false,
          origin: fromPlanner.origin,
          result: const LedgerCompletionSuccess(
              ingredientsRescued: 2,
              ingredientsRescuedList: ['Zucchini', 'Feta'],
              lifetimeIngredientsRescued: 2),
        ),
        LedgerVerdict.counted,
      );
      expect(fromPlanner.origin!.ledgerSourceValue, 'fridge_clearer');
      expect(
        LedgerService.computeRescuedIngredients(
          enteredIngredients: fromPlanner.originEnteredIngredients!,
          cookedIngredients: fromPlanner.ingredients,
        ),
        ['Zucchini', 'Feta'],
        reason: 'the same ingredients a direct cook would have credited',
      );
    });

    test('the local cook-session store is the third hop and also preserves it',
        () async {
      // Resume-after-backgrounding goes through SharedPreferences, not jsonb.
      SharedPreferences.setMockInitialValues({});
      final storage = CookSessionStorageService();
      final generated = testRecipe('Rescue Dish',
          origin: RecipeOrigin.fridgeClearer, entered: ['Zucchini']);

      await storage.saveActiveSession(
        recipe: generated,
        cookStarted: true,
        cookPaused: true,
        activeStepIndex: 0,
        completedSteps: <int>{},
        activeRemaining: const Duration(minutes: 3),
        currentPortions: 2,
        surface: CookModeSurface.weeklyPlanner,
        isReCook: false,
      );

      final resumed = await storage.loadActiveSession();
      expect(resumed, isNotNull);
      expect(resumed!.recipe.origin, RecipeOrigin.fridgeClearer,
          reason: 'a resumed planner cook must still count as a rescue');
      expect(resumed.recipe.originEnteredIngredients, ['Zucchini']);
    });
  });

  group('lifecycle', () {
    testWidgets('leaving My recipes mid-load does not setState after dispose',
        (tester) async {
      final service = _service(FakeSavedRecipesBackend());
      await CookSessionStorageService().addRecentlyCooked(testRecipe('Ragu'));

      await tester.pumpWidget(_wrapApp(service));
      // One frame only — _loadDerived() is still in flight.
      await tester.pump();

      // Replace the whole tree, disposing the screen mid-async.
      await tester.pumpWidget(const MaterialApp(home: _StubScreen('gone')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'the saved-recipes stream subscription is released when the screen goes '
        'away, and later mutations do not throw', (tester) async {
      final service = _service(FakeSavedRecipesBackend());
      await service.save(testRecipe('One'));

      await tester.pumpWidget(_wrapApp(service));
      await tester.pumpAndSettle();
      expect(find.text('One'), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(home: _StubScreen('gone')));
      await tester.pumpAndSettle();

      // Mutating after the listener is gone must be inert, not an error.
      await service.save(testRecipe('Two'));
      await service.unsave(SavedRecipesService.recipeKeyFor('One'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('closing the planner add sheet releases its picker stream',
        (tester) async {
      final service = _service(FakeSavedRecipesBackend());
      await service.save(testRecipe('Saved Dish'));

      final router = GoRouter(
        initialLocation: AppRoutes.weeklyPlan,
        routes: [
          GoRoute(
            path: AppRoutes.weeklyPlan,
            builder: (c, s) =>
                WeeklyPlannerScreen(savedRecipesService: service),
          ),
          GoRoute(
              path: AppRoutes.home, builder: (c, s) => const _StubScreen('h')),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.text('+ Add Meal').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('My recipes'));
      await tester.pumpAndSettle();
      expect(find.text('Saved Dish'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      await service.save(testRecipe('After Close'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('accessibility: the no-scroll Home at large text', () {
    // MEASURED, 2026-08-20 review: on a 360x640 phone Home survives text
    // scaling up to and including 2.4, and overflows by 10px at 2.8 and 69px
    // at 3.2. That covers all of Android (settings cap at 2.0) and iOS up to
    // roughly AX3; iOS AX4/AX5 (~2.8-3.1) will clip the rescue strip.
    //
    // Deliberately NOT "fixed" here: the only two fixes are making Home
    // scroll (contradicts the signed one-screen rule) or clamping text scale
    // (an accessibility regression). Both are Harris's call, not a reviewer's.
    // This locks the range that DOES work so a future change cannot quietly
    // narrow it.
    Widget wrapHome(double scale) {
      final router = GoRouter(
        initialLocation: AppRoutes.home,
        observers: [routeObserver],
        routes: [
          GoRoute(
              path: AppRoutes.home,
              builder: (c, s) => const HomeDashboardScreen()),
        ],
      );
      return ChangeNotifierProvider<UserProfileController>.value(
        value: UserProfileController(UserProfileService()),
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      );
    }

    for (final scale in kHomeSupportedTextScales) {
      testWidgets('does not overflow at textScale $scale on a 360x640 phone',
          (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(wrapHome(scale));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'Home does not scroll, so an overflow is a real failure');
      });
    }
  });
}
