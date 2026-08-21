import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/fridge_clearer_screen.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/services/saved_recipes_service.dart';
import 'package:optimeal/widgets/generated_recipe_actions_sheet.dart';
import 'package:optimeal/widgets/save_recipe_bookmark_button.dart';

import '../support/fake_saved_recipes_backend.dart';

/// Covers the gap closed on 2026-08-21: a freshly generated recipe could not
/// be saved until after it had been cooked, because neither generation-result
/// surface mounted the universal bookmark. The earliest save point was the
/// post-cook verdict card.
///
/// Both surfaces hold a plain [CookModeRecipePayload] with nothing persisted
/// yet, which is exactly what [SaveRecipeBookmarkButton] already expects —
/// identity is the title, and `save` writes the payload inline. There is no
/// not-yet-saved special case, so these tests assert ordinary behaviour.
Widget _wrap(Widget child) {
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(path: AppRoutes.home, builder: (c, s) => Scaffold(body: child)),
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

  group('GeneratedRecipeCard (Fridge Clearer result)', () {
    Widget card(SavedRecipesService service, {String title = 'Fresh Bake'}) =>
        _wrap(SingleChildScrollView(
          child: GeneratedRecipeCard(
            recipe: testRecipe(title),
            portions: 2,
            onCookNow: () {},
            onPlanForDay: () {},
            onTryAnother: () {},
            service: service,
          ),
        ));

    testWidgets('mounts the universal bookmark, outline when unsaved',
        (tester) async {
      await tester.pumpWidget(card(_service(FakeSavedRecipesBackend())));
      await tester.pumpAndSettle();

      expect(find.byType(SaveRecipeBookmarkButton), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
    });

    testWidgets('bookmark saves the freshly generated recipe', (tester) async {
      final backend = FakeSavedRecipesBackend();
      await tester.pumpWidget(card(_service(backend)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SaveRecipeBookmarkButton));
      await tester.pumpAndSettle();

      expect(backend.rows, hasLength(1));
      expect(backend.rows.single['title'], 'Fresh Bake');
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    });

    testWidgets('Cook Now is still the only primary action', (tester) async {
      await tester.pumpWidget(card(_service(FakeSavedRecipesBackend())));
      await tester.pumpAndSettle();

      // The bookmark is quiet: it must not have become a third button in the
      // action row, and must not have displaced Cook Now.
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('🔥 Cook Now'), findsOneWidget);
    });
  });

  group('GeneratedRecipeActionsSheet', () {
    Widget sheet(SavedRecipesService service) => _wrap(GeneratedRecipeActionsSheet(
          recipe: testRecipe('Sheet Recipe'),
          sourceLabel: 'Custom AI Recipe Creator',
          surface: CookModeSurface.customAiRecipeCreator,
          service: service,
        ));

    testWidgets('mounts the universal bookmark, outline when unsaved',
        (tester) async {
      await tester.pumpWidget(sheet(_service(FakeSavedRecipesBackend())));
      await tester.pumpAndSettle();

      expect(find.byType(SaveRecipeBookmarkButton), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
    });

    testWidgets('bookmark saves the freshly generated recipe', (tester) async {
      final backend = FakeSavedRecipesBackend();
      await tester.pumpWidget(sheet(_service(backend)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SaveRecipeBookmarkButton));
      await tester.pumpAndSettle();

      expect(backend.rows, hasLength(1));
      expect(backend.rows.single['title'], 'Sheet Recipe');
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    });

    testWidgets('both existing actions survive alongside it', (tester) async {
      await tester.pumpWidget(sheet(_service(FakeSavedRecipesBackend())));
      await tester.pumpAndSettle();

      expect(find.text('🔥 Cook Now'), findsOneWidget);
      expect(find.text('📅 Plan for Day'), findsOneWidget);
    });
  });
}
