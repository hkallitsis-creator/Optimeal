import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/models/recipe_origin.dart';
import 'package:optimeal/models/user_profile.dart';
import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/fridge_clearer_screen.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/chef_service.dart';
import 'package:optimeal/services/user_profile_service.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/widgets/generated_recipe_actions_sheet.dart';

/// Fridge Clearer redesign (2026-08-22): the one-screen input and the
/// two-stage ideas moment.
///
/// Both stages go through `askChefHarris`, so a fake that records its calls is
/// enough to drive the whole flow with no network — and to assert the thing
/// the two-stage split most easily breaks: that the expensive call fires only
/// after the user has chosen, and that rescue provenance survives it.

/// Records every call and replies with whatever the test queued for that
/// surface.
class _FakeChefService extends ChefService {
  _FakeChefService({required this.ideasReply, required this.recipeReply});

  final String ideasReply;
  final String recipeReply;

  final List<String> surfaces = <String>[];
  final List<String> userQueries = <String>[];
  final List<String?> staticBlocks = <String?>[];

  int get ideasCalls =>
      surfaces.where((s) => s == kChefCallSurfaceFridgeIdeas).length;
  int get recipeCalls =>
      surfaces.where((s) => s == kChefCallSurfaceFridgeClearer).length;

  @override
  Future<String> askChefHarris({
    required String userQuery,
    String? recipeTitle,
    UserProfile? profile,
    bool forceJsonObject = false,
    List<String>? recentDishTitles,
    bool excludeDishFormats = true,
    String? recipeContext,
    List<({bool isUser, String text})>? conversationHistory,
    String? staticPromptBlock,
    String? surface,
    int? maxTokens,
  }) async {
    surfaces.add(surface ?? '<null>');
    userQueries.add(userQuery);
    staticBlocks.add(staticPromptBlock);
    return surface == kChefCallSurfaceFridgeIdeas ? ideasReply : recipeReply;
  }
}

const String _ideasReply = '''
{"ideas":[
  {"title":"Zucchini Frittata","total_time_minutes":20,
   "ingredients_cleared":["Zucchini","Eggs"],"ingredients_left":["Potatoes"]},
  {"title":"Everything Tray Bake","total_time_minutes":40,
   "ingredients_cleared":["Zucchini","Eggs","Potatoes"],"ingredients_left":[]},
  {"title":"Potato Soup","total_time_minutes":30,
   "ingredients_cleared":["Potatoes"],"ingredients_left":["Zucchini","Eggs"]}
]}
''';

const String _recipeReply = '''
{"title":"Zucchini Frittata","description":"A quick skillet frittata.",
 "curriculum_lesson_id":"sauteing",
 "ingredients":[{"name":"Zucchini","amount":300,"unit":"g","cut":"slice"},
                {"name":"Eggs","amount":4,"unit":"piece","cut":"none"}],
 "kitchen_gear":["Pan"],
 "steps":[{"title":"Heat the pan","duration_minutes":3,"heat":"medium",
           "ingredients_added":[],"sensory_cue":"oil_shimmers",
           "bullets":["Wait for the shimmer."]},
          {"title":"Cook it through","duration_minutes":8,"heat":"medium",
           "ingredients_added":["Zucchini","Eggs"],"sensory_cue":"no_cue",
           "bullets":["Do not stir once it sets."]}]}
''';

CookModeRecipePayload? poppedPayload;

Widget _wrap(_FakeChefService chef, {bool returnPayload = false}) {
  final router = GoRouter(
    initialLocation: '/fridge',
    routes: [
      GoRoute(
        path: '/fridge',
        builder: (context, state) => FridgeClearerScreen(
          chefService: chef,
          returnCookModePayload: returnPayload,
        ),
      ),
      GoRoute(
          path: AppRoutes.home,
          builder: (c, s) => const Scaffold(body: Text('home'))),
      GoRoute(
          path: AppRoutes.onePanCookingRoadmap,
          builder: (c, s) => const Scaffold(body: Text('cook mode'))),
    ],
  );

  return ChangeNotifierProvider(
    create: (_) => UserProfileController(UserProfileService()),
    child: MaterialApp.router(routerConfig: router),
  );
}

/// The planner path pushes this screen and awaits a payload, so it needs a
/// host route to pop back to.
Widget _wrapAsPlannerPicker(_FakeChefService chef) {
  final router = GoRouter(
    initialLocation: '/host',
    routes: [
      GoRoute(
        path: '/host',
        builder: (context, state) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final result =
                    await context.push<Object?>('/fridge');
                if (result is CookModeRecipePayload) poppedPayload = result;
              },
              child: const Text('open picker'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/fridge',
        builder: (context, state) => FridgeClearerScreen(
            chefService: chef, returnCookModePayload: true),
      ),
      GoRoute(
          path: AppRoutes.home,
          builder: (c, s) => const Scaffold(body: Text('home'))),
    ],
  );
  return ChangeNotifierProvider(
    create: (_) => UserProfileController(UserProfileService()),
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

/// Selects two suggestion chips and presses the CTA.
Future<void> _generateIdeas(WidgetTester tester) async {
  await tester.tap(find.text('Zucchini'));
  await tester.tap(find.text('Eggs'));
  await tester.pump();
  await tester.tap(find.textContaining('Let\'s cook'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    poppedPayload = null;
  });

  _FakeChefService chef() => _FakeChefService(
      ideasReply: _ideasReply, recipeReply: _recipeReply);

  group('the input screen', () {
    testWidgets('is one screen: hero card, one settings card, pinned CTA',
        (tester) async {
      await _pump(tester, _wrap(chef()));

      expect(find.text('What needs using up?'), findsOneWidget);
      expect(find.textContaining('Pantry staples are assumed'), findsOneWidget);

      // ONE settings card, three rows — not three cards with headlines.
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Gear'), findsOneWidget);
      expect(find.text('For'), findsOneWidget);

      // The cut explainers are gone.
      expect(find.textContaining('Pick a quick time-box'), findsNothing);
      expect(find.textContaining('Select one or more'), findsNothing);
      expect(find.textContaining('Defaults to your profile'), findsNothing);

      // The page itself does not scroll.
      expect(find.byType(ListView), findsNothing);
      expect(find.textContaining('Let\'s cook'), findsOneWidget);
    });

    testWidgets('every selector wraps — nothing scrolls sideways',
        (tester) async {
      await _pump(tester, _wrap(chef()));
      // Kit rule: controls wrap, never clip. A horizontal scroll view here is
      // exactly what clipped "45+ M…" and "4 …".
      final scrollables = tester
          .widgetList<ScrollView>(find.byType(ScrollView, skipOffstage: false))
          .where((s) => s.scrollDirection == Axis.horizontal);
      expect(scrollables, isEmpty);
    });

    testWidgets('suggestion chips select and deselect', (tester) async {
      await _pump(tester, _wrap(chef()));

      await tester.tap(find.text('Zucchini'));
      await tester.pump();
      expect(_chipSelected(tester, 'Zucchini'), isTrue);

      await tester.tap(find.text('Zucchini'));
      await tester.pump();
      expect(_chipSelected(tester, 'Zucchini'), isFalse);
    });

    testWidgets('a typed ingredient joins the same wrap, removable',
        (tester) async {
      await _pump(tester, _wrap(chef()));

      await tester.enterText(find.byType(TextField), 'Leftover rice');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Leftover rice'), findsOneWidget);
      expect(_chipSelected(tester, 'Leftover rice'), isTrue);
      // ✕ affordance, in the same wrap as the suggestions.
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.text('Leftover rice'));
      await tester.pumpAndSettle();
      expect(find.text('Leftover rice'), findsNothing);
    });

    testWidgets('the For row silently defaults from the profile',
        (tester) async {
      await _pump(tester, _wrap(chef()));
      // UserProfile.empty() defaults householdServings to 1, and that segment
      // is selected with no explainer line telling the user so.
      expect(_chipSelected(tester, '1'), isTrue);
      expect(_chipSelected(tester, '4'), isFalse);

      await tester.tap(find.text('4'));
      await tester.pump();
      expect(_chipSelected(tester, '4'), isTrue);
      expect(_chipSelected(tester, '1'), isFalse);
    });

    testWidgets('gear is text chips with no per-chip icons', (tester) async {
      await _pump(tester, _wrap(chef()));
      for (final label in ['Pan', 'One-pot', 'Oven tray', 'Wok']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // The only icons on the input screen are the three settings-row glyphs,
      // the add button and the back button — never one per chip.
      expect(find.byIcon(Icons.kitchen_outlined), findsNothing);
      expect(find.byIcon(Icons.egg_alt_outlined), findsNothing);
    });
  });

  group('stage 1 — the menu', () {
    testWidgets('one call, three cards, clearance line per card',
        (tester) async {
      final fake = chef();
      await _pump(tester, _wrap(fake));
      await _generateIdeas(tester);

      expect(fake.ideasCalls, 1);
      expect(fake.recipeCalls, 0,
          reason: 'no full recipe is generated before a choice');

      expect(find.text('Zucchini Frittata'), findsOneWidget);
      expect(find.text('Everything Tray Bake'), findsOneWidget);
      expect(find.text('Potato Soup'), findsOneWidget);
      expect(find.text('20 min'), findsOneWidget);
    });

    testWidgets('the clearance line is computed from the entered list',
        (tester) async {
      await _pump(tester, _wrap(chef()));
      await _generateIdeas(tester);

      // Entered: Zucchini, Eggs. The frittata claims both → clears 2 of 2,
      // even though the model also claimed Potatoes were left over (the user
      // never entered potatoes, so they cannot appear in either count).
      // Both the frittata AND the tray bake clear both entered ingredients —
      // the tray bake also claims Potatoes, which the user does not have, so
      // it cannot count toward either number.
      expect(find.text('Clears 2 of your 2 ingredients'), findsNWidgets(2));
      // The soup claims only Potatoes, which the user does not have → 0 of 2.
      expect(find.textContaining('Clears 0 of your 2'), findsOneWidget);
    });

    testWidgets('the "X stays" case names what is left', (tester) async {
      await _pump(tester, _wrap(chef()));
      await tester.tap(find.text('Zucchini'));
      await tester.tap(find.text('Eggs'));
      await tester.tap(find.text('Potatoes'));
      await tester.pump();
      await tester.tap(find.textContaining('Let\'s cook'));
      await tester.pumpAndSettle();

      // Frittata clears Zucchini + Eggs of three entered. The verb is always
      // "stay": agreement follows the noun, and "potatoes stays" is wrong.
      expect(find.text('Clears 2 of your 3 — potatoes stays.'), findsNothing);
      expect(find.text('Clears 2 of your 3 — potatoes stay.'), findsOneWidget);
      // The tray bake clears all three.
      expect(find.text('Clears 3 of your 3 ingredients'), findsOneWidget);
    });

    testWidgets('the header names the actual ingredients', (tester) async {
      await _pump(tester, _wrap(chef()));
      await _generateIdeas(tester);
      expect(find.textContaining('zucchini'), findsWidgets);
      expect(find.text('Three ways to clear it'), findsNothing);
    });

    testWidgets('there is no regenerate affordance in this flow',
        (tester) async {
      await _pump(tester, _wrap(chef()));
      await _generateIdeas(tester);

      expect(find.textContaining('Try Another'), findsNothing);
      expect(find.textContaining('Regenerate'), findsNothing);
    });

    testWidgets('back returns to the input with selections intact',
        (tester) async {
      await _pump(tester, _wrap(chef()));
      await _generateIdeas(tester);
      expect(find.text('Zucchini Frittata'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('What needs using up?'), findsOneWidget);
      expect(_chipSelected(tester, 'Zucchini'), isTrue);
      expect(_chipSelected(tester, 'Eggs'), isTrue);
    });

    testWidgets('a malformed reply shows the error card, invents nothing',
        (tester) async {
      final fake = _FakeChefService(
          ideasReply: 'Sorry, I can\'t do that.', recipeReply: _recipeReply);
      await _pump(tester, _wrap(fake));
      await _generateIdeas(tester);

      expect(find.textContaining('Couldn\'t come up with ideas'),
          findsOneWidget);
      // Still on the input screen — no fabricated menu.
      expect(find.text('What needs using up?'), findsOneWidget);
      expect(fake.recipeCalls, 0);
    });

    testWidgets('the static block is sent separately from the query',
        (tester) async {
      final fake = chef();
      await _pump(tester, _wrap(fake));
      await _generateIdeas(tester);

      // Prompt-caching rule (1c76d03): the byte-identical half travels as
      // staticPromptBlock, never concatenated into userQuery.
      expect(fake.staticBlocks.first, isNotNull);
      expect(fake.staticBlocks.first, contains('"ingredients_cleared"'));
      expect(fake.userQueries.first, isNot(contains('"ingredients_cleared"')));
      expect(fake.userQueries.first, contains('Zucchini'));
    });
  });

  group('stage 2 — the recipe, after the choice', () {
    testWidgets('choosing an idea triggers exactly one recipe call',
        (tester) async {
      final fake = chef();
      await _pump(tester, _wrap(fake));
      await _generateIdeas(tester);

      await tester.tap(find.text('Zucchini Frittata'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(fake.ideasCalls, 1);
      expect(fake.recipeCalls, 1);
      // Anchored on the chosen idea.
      expect(fake.userQueries.last, contains('Zucchini Frittata'));
    });

    testWidgets('the result arrives in the shared Cook/Save/Plan sheet',
        (tester) async {
      await _pump(tester, _wrap(chef()));
      await _generateIdeas(tester);
      await tester.tap(find.text('Zucchini Frittata'));
      // Not pumpAndSettle: the sheet's bookmark subscribes to the shared
      // SavedRecipesService, which never goes quiet without Supabase.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(GeneratedRecipeActionsSheet), findsOneWidget);
      expect(find.text('Cook Now'), findsOneWidget);
      expect(find.text('Plan for Day'), findsOneWidget);
    });

    testWidgets('the stage-2 recipe carries full rescue provenance',
        (tester) async {
      // The thing the two-stage split could most easily have broken.
      await _pump(tester, _wrapAsPlannerPicker(chef()));
      await tester.tap(find.text('open picker'));
      await tester.pumpAndSettle();

      await _generateIdeas(tester);
      await tester.tap(find.text('Zucchini Frittata'));
      await tester.pumpAndSettle();

      expect(poppedPayload, isNotNull);
      expect(poppedPayload!.origin, RecipeOrigin.fridgeClearer);
      expect(poppedPayload!.origin!.isRescueEligible, isTrue);
      expect(poppedPayload!.originEnteredIngredients,
          containsAll(<String>['Zucchini', 'Eggs']));
    });

    testWidgets('the planner path lands on the same ideas screen',
        (tester) async {
      await _pump(tester, _wrapAsPlannerPicker(chef()));
      await tester.tap(find.text('open picker'));
      await tester.pumpAndSettle();

      // Same input screen, same ideas screen — only what happens after the
      // choice differs.
      expect(find.text('What needs using up?'), findsOneWidget);
      await _generateIdeas(tester);
      expect(find.text('Everything Tray Bake'), findsOneWidget);
      expect(find.textContaining('Clears'), findsWidgets);
    });

    testWidgets('a malformed stage-2 reply keeps the menu and shows an error',
        (tester) async {
      final fake =
          _FakeChefService(ideasReply: _ideasReply, recipeReply: 'nope');
      await _pump(tester, _wrap(fake));
      await _generateIdeas(tester);
      await tester.tap(find.text('Zucchini Frittata'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Couldn\'t build that recipe'), findsOneWidget);
      // The three ideas are still there to choose from again.
      expect(find.text('Everything Tray Bake'), findsOneWidget);
      expect(find.byType(GeneratedRecipeActionsSheet), findsNothing);
    });
  });
}

/// Reads a chip's selected state from its champagne fill — the kit rule says
/// selection IS the fill, so asserting on it is asserting the rule.
bool _chipSelected(WidgetTester tester, String label) {
  final material = tester.widget<Material>(
    find.ancestor(of: find.text(label), matching: find.byType(Material)).first,
  );
  return material.color == const Color(0xFFF7DBCB);
}
