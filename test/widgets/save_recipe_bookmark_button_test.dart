import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/services/saved_recipes_service.dart';
import 'package:optimeal/widgets/ledger_verdict_sheet.dart';
import 'package:optimeal/widgets/save_recipe_bookmark_button.dart';
import 'package:optimeal/widgets/waste_ledger_celebration_sheet.dart';

import '../support/fake_saved_recipes_backend.dart';

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

  group('SaveRecipeBookmarkButton', () {
    testWidgets('outline when unsaved, filled after tapping', (tester) async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);

      await tester.pumpWidget(_wrap(SaveRecipeBookmarkButton(
          recipe: testRecipe('Toggle Me'), service: service)));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_rounded), findsNothing);

      await tester.tap(find.byType(SaveRecipeBookmarkButton));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border_rounded), findsNothing);
      expect(backend.rows, hasLength(1));
    });

    testWidgets('tapping a filled bookmark unsaves', (tester) async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);
      await service.save(testRecipe('Toggle Me'));

      await tester.pumpWidget(_wrap(SaveRecipeBookmarkButton(
          recipe: testRecipe('Toggle Me'), service: service)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);

      await tester.tap(find.byType(SaveRecipeBookmarkButton));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
      expect(backend.rows, isEmpty);
    });

    testWidgets('one mechanism: toggling on one surface updates every other',
        (tester) async {
      // Two bookmarks for the SAME recipe, standing in for two surfaces open
      // at once (e.g. a saved card and a recently-cooked row).
      final service = _service(FakeSavedRecipesBackend());
      final recipe = testRecipe('Shared Recipe');

      await tester.pumpWidget(_wrap(Column(children: [
        SaveRecipeBookmarkButton(recipe: recipe, service: service),
        SaveRecipeBookmarkButton(recipe: recipe, service: service),
      ])));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark_border_rounded), findsNWidgets(2));

      await tester.tap(find.byType(SaveRecipeBookmarkButton).first);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark_rounded), findsNWidgets(2),
          reason: 'both surfaces reflect the same saved state');
    });
  });

  group('post-cook verdict cards', () {
    // The signed post-cook sequence is load-bearing: the exit-to-Home CTA is
    // the only working way out of a finished cook. These two tests exist so
    // adding anything to either card can never silently push it off the end.
    Finder lastColumnChild(Type sheetType) {
      return find.descendant(
        of: find.byType(sheetType),
        matching: find.byType(Column),
      );
    }

    void expectCtaIsLast(WidgetTester tester, Type sheetType) {
      final column = tester.widget<Column>(lastColumnChild(sheetType).first);
      final last = column.children.last;
      expect(
        find
            .descendant(
                of: find.byWidget(last), matching: find.text('Back to Home'))
            .evaluate(),
        isNotEmpty,
        reason: 'the exit-to-Home CTA must remain the LAST element',
      );
    }

    testWidgets('LedgerVerdictSheet keeps the CTA last, with a bookmark added',
        (tester) async {
      final service = _service(FakeSavedRecipesBackend());
      await tester.pumpWidget(_wrap(LedgerVerdictSheet(
        line: 'This is the verdict line.',
        recipe: testRecipe('Cooked Thing'),
        service: service,
      )));
      await tester.pumpAndSettle();

      expect(find.text('This is the verdict line.'), findsOneWidget);
      expect(find.byType(SaveRecipeBookmarkButton), findsOneWidget);
      expectCtaIsLast(tester, LedgerVerdictSheet);
    });

    testWidgets(
        'WasteLedgerCelebrationSheet keeps the CTA last, with a bookmark',
        (tester) async {
      final service = _service(FakeSavedRecipesBackend());
      await tester.pumpWidget(_wrap(WasteLedgerCelebrationSheet(
        ingredientsRescued: const ['Zucchini'],
        lifetimeIngredientsRescued: 4,
        recipe: testRecipe('Cooked Thing'),
        service: service,
      )));
      await tester.pumpAndSettle();

      expect(find.byType(SaveRecipeBookmarkButton), findsOneWidget);
      expectCtaIsLast(tester, WasteLedgerCelebrationSheet);
    });

    testWidgets('the verdict bookmark is quiet: no copy, nothing to dismiss',
        (tester) async {
      final service = _service(FakeSavedRecipesBackend());
      await tester.pumpWidget(_wrap(LedgerVerdictSheet(
        line: 'This is the verdict line.',
        recipe: testRecipe('Cooked Thing'),
        service: service,
      )));
      await tester.pumpAndSettle();

      // Exactly two pieces of text: the verdict line and the CTA. The
      // bookmark adds no prompt of its own.
      expect(find.byType(Text), findsNWidgets(2));
    });

    testWidgets('no bookmark at all when there is no recipe (demo cook)',
        (tester) async {
      await tester.pumpWidget(
          _wrap(const LedgerVerdictSheet(line: 'This is the verdict line.')));
      await tester.pumpAndSettle();

      expect(find.byType(SaveRecipeBookmarkButton), findsNothing);
      expectCtaIsLast(tester, LedgerVerdictSheet);
    });

    testWidgets('the verdict bookmark actually saves', (tester) async {
      final backend = FakeSavedRecipesBackend();
      await tester.pumpWidget(_wrap(LedgerVerdictSheet(
        line: 'This is the verdict line.',
        recipe: testRecipe('Cooked Thing'),
        service: _service(backend),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SaveRecipeBookmarkButton));
      await tester.pumpAndSettle();

      expect(backend.rows, hasLength(1));
      expect(backend.rows.single['title'], 'Cooked Thing');
    });
  });
}
