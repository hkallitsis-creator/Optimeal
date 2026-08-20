import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/models/cook_mode_recipe_codec.dart';
import 'package:optimeal/models/recipe_origin.dart';
import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/my_recipes_screen.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/services/saved_recipes_service.dart';
import 'package:optimeal/widgets/recipe_provenance_badges.dart';
import 'package:optimeal/widgets/save_recipe_bookmark_button.dart';

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
    initialLocation: AppRoutes.myRecipes,
    routes: [
      GoRoute(
        path: AppRoutes.myRecipes,
        builder: (context, state) => MyRecipesScreen(service: service),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const _StubScreen('home'),
      ),
      GoRoute(
        path: AppRoutes.recipe,
        builder: (context, state) {
          final extra = state.extra;
          return _StubScreen(
              'details:${extra is CookModeRecipePayload ? extra.title : 'none'}');
        },
      ),
      GoRoute(
        path: AppRoutes.weeklyPlan,
        builder: (context, state) => const _StubScreen('weekly'),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

SavedRecipesService _service(FakeSavedRecipesBackend backend) =>
    SavedRecipesService(
      backend: backend,
      sessionStorage: CookSessionStorageService(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('empty states', () {
    testWidgets('nothing saved and nothing cooked shows the full empty state',
        (tester) async {
      await tester.pumpWidget(_wrap(_service(FakeSavedRecipesBackend())));
      await tester.pumpAndSettle();

      expect(find.text('Your shelf is empty.'), findsOneWidget);
      expect(find.text('Recipes you bookmark or cook will land here.'),
          findsOneWidget);
      // The designed glyph, not a bare string.
      expect(find.byIcon(Icons.bookmark_border_rounded), findsWidgets);
      // No log section at all.
      expect(find.text('Recently cooked'), findsNothing);
    });

    testWidgets(
        'nothing saved but cooks present shows the inline empty-saved treatment '
        'ABOVE the log, not the full-screen state', (tester) async {
      await CookSessionStorageService().addRecentlyCooked(testRecipe('Ragu'));

      await tester.pumpWidget(_wrap(_service(FakeSavedRecipesBackend())));
      await tester.pumpAndSettle();

      expect(find.text('Your shelf is empty.'), findsNothing);
      expect(find.text('Nothing saved yet.'), findsOneWidget);
      expect(find.text('Recently cooked'), findsOneWidget);
      expect(find.text('Ragu'), findsOneWidget);
    });
  });

  group('section weight hierarchy', () {
    testWidgets('saved entries are cards and cooked entries are quiet rows',
        (tester) async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);
      await service.save(testRecipe('Saved Dish'));
      await CookSessionStorageService()
          .addRecentlyCooked(testRecipe('Cooked Dish'));

      await tester.pumpWidget(_wrap(service));
      await tester.pumpAndSettle();

      expect(find.text('Saved Dish'), findsOneWidget);
      expect(find.text('Cooked Dish'), findsOneWidget);

      // Saved = a real card: cream Material with a shadowed, bordered box.
      final savedBox = tester.widget<Container>(find
          .ancestor(
              of: find.text('Saved Dish'), matching: find.byType(Container))
          .first);
      final savedDecoration = savedBox.decoration as BoxDecoration;
      expect(savedDecoration.boxShadow, isNotNull,
          reason: 'saved entries carry card weight');
      expect(savedDecoration.border, isNotNull);

      // Cooked = a quiet row: no Container decoration wrapping it at all.
      expect(
        find.ancestor(
            of: find.text('Cooked Dish'), matching: find.byType(Container)),
        findsNothing,
        reason: 'the log must stay visually lighter than the cards',
      );
    });
  });

  group('saved card content', () {
    testWidgets(
        'a Fridge Clearer recipe shows the leaf badge; a custom one does not',
        (tester) async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);
      await service
          .save(testRecipe('Rescue Dish', origin: RecipeOrigin.fridgeClearer));
      await service.save(testRecipe('Craving Dish',
          origin: RecipeOrigin.customAiRecipeCreator));

      await tester.pumpWidget(_wrap(service));
      await tester.pumpAndSettle();

      expect(find.byType(ProvenanceLeafBadge), findsOneWidget);
      expect(
          find.descendant(
              of: find.ancestor(
                  of: find.text('Rescue Dish'), matching: find.byType(Row)),
              matching: find.byType(ProvenanceLeafBadge)),
          findsOneWidget);
    });

    testWidgets(
        'a never-cooked saved recipe shows the not-cooked marker and no count',
        (tester) async {
      final service = _service(FakeSavedRecipesBackend());
      await service.save(testRecipe('Fresh Save'));

      await tester.pumpWidget(_wrap(service));
      await tester.pumpAndSettle();

      expect(find.text('Not cooked yet'), findsOneWidget);
      expect(find.textContaining('0 times'), findsNothing);
      expect(find.textContaining('Cooked 0'), findsNothing);
    });

    testWidgets('a cooked saved recipe shows the derived count instead',
        (tester) async {
      final service = _service(FakeSavedRecipesBackend());
      await CookSessionStorageService()
          .addRecentlyCooked(testRecipe('Repeat Dish'));
      await service.save(testRecipe('Repeat Dish'));

      await tester.pumpWidget(_wrap(service));
      await tester.pumpAndSettle();

      expect(find.text('Cooked 1 time'), findsOneWidget);
      expect(find.text('Not cooked yet'), findsNothing);
    });

    testWidgets('tapping a saved card opens recipe details with that payload',
        (tester) async {
      final service = _service(FakeSavedRecipesBackend());
      await service.save(testRecipe('Open Me'));

      await tester.pumpWidget(_wrap(service));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Me'));
      await tester.pumpAndSettle();

      expect(find.text('details:Open Me'), findsOneWidget);
    });

    testWidgets('the calendar action opens the existing weekday picker sheet',
        (tester) async {
      final service = _service(FakeSavedRecipesBackend());
      await service.save(testRecipe('Plan Me'));

      await tester.pumpWidget(_wrap(service));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.calendar_month_rounded));
      await tester.pumpAndSettle();

      // WeekdayPickerSheet's own content, unchanged.
      expect(find.text('Plan for which day?'), findsOneWidget);
      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('Sunday'), findsOneWidget);
    });
  });

  group('promote from history', () {
    testWidgets(
        'tapping the bookmark on a cooked row moves it into Saved, provenance intact',
        (tester) async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);
      await CookSessionStorageService().addRecentlyCooked(
          testRecipe('Promote Me', origin: RecipeOrigin.fridgeClearer));

      await tester.pumpWidget(_wrap(service));
      await tester.pumpAndSettle();

      // Before: only in the log, nothing saved.
      expect(find.text('Nothing saved yet.'), findsOneWidget);
      expect(find.byType(ProvenanceLeafBadge), findsNothing);
      expect(find.byIcon(Icons.bookmark_border_rounded), findsWidgets);

      await tester.tap(find.byType(SaveRecipeBookmarkButton).last);
      await tester.pumpAndSettle();

      // After: a saved card exists, carrying its Fridge Clearer badge, and the
      // log row's bookmark is now filled.
      expect(find.text('Nothing saved yet.'), findsNothing);
      expect(find.byType(ProvenanceLeafBadge), findsOneWidget);
      expect(find.text('Promote Me'), findsNWidgets(2),
          reason: 'the recipe is now in both sections');
      expect(find.byIcon(Icons.bookmark_rounded), findsNWidgets(2),
          reason: 'filled on the new card AND on the log row');

      final saved = backend.rows.single;
      expect(saved['origin'], 'fridgeClearer');
    });
  });

  group('ordering', () {
    testWidgets('saved recipes render in the service order, not re-sorted',
        (tester) async {
      // Rows seeded directly with explicit timestamps. A real
      // `Future.delayed` between two saves would never complete here —
      // testWidgets runs in fake async, so wall-clock timers hang the test.
      final backend = FakeSavedRecipesBackend();
      await backend.upsert({
        'user_id': 'user-1',
        'recipe_key': SavedRecipesService.recipeKeyFor('Alpha'),
        'title': 'Alpha',
        'recipe_payload': cookModeRecipeToJson(testRecipe('Alpha')),
        'origin': null,
        'last_touched_at': '2026-08-01T10:00:00Z',
      });
      await backend.upsert({
        'user_id': 'user-1',
        'recipe_key': SavedRecipesService.recipeKeyFor('Zulu'),
        'title': 'Zulu',
        'recipe_payload': cookModeRecipeToJson(testRecipe('Zulu')),
        'origin': null,
        'last_touched_at': '2026-08-19T10:00:00Z',
      });
      final service = _service(backend);

      await tester.pumpWidget(_wrap(service));
      await tester.pumpAndSettle();

      // Most recent activity first — NOT alphabetical.
      final alphaY = tester.getTopLeft(find.text('Alpha')).dy;
      final zuluY = tester.getTopLeft(find.text('Zulu')).dy;
      expect(zuluY, lessThan(alphaY));
    });
  });

  group('navigation', () {
    testWidgets('back lands on Home (depth-1, no home glyph)', (tester) async {
      await tester.pumpWidget(_wrap(_service(FakeSavedRecipesBackend())));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.home_outlined), findsNothing,
          reason: 'depth-1 screens get a back button only');

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
    });
  });
}
