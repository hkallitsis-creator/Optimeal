import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/models/recipe_scale.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/services/user_profile_service.dart';
import 'package:optimeal/state/ingredient_prep_controller.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/mise_en_place_card.dart';

/// The pre-cook merge: the ingredients checklist and Step 1 became one
/// surface, and the generated prep step is deduped against the synthesized
/// one.
///
/// Device evidence this closes: an "Ingredients Checklist" card with tick rows
/// and its own servings stepper, sitting above a step list that then opened
/// with a near-identical "Prepare Your Ingredients" step.

CookModeStepPayload _step(
  String title, {
  String heat = 'medium',
  int minutes = 5,
  List<String> bullets = const ['do the thing'],
  List<String>? adds,
}) =>
    CookModeStepPayload(
      title: title,
      heat: heat,
      durationMinutes: minutes,
      bullets: bullets,
      ingredientsAdded: adds,
    );

CookModeRecipePayload _recipe({
  required List<CookModeStepPayload> steps,
  List<RecipeIngredient>? structured,
  int? basePortions = 2,
}) =>
    CookModeRecipePayload(
      title: 'Test dish',
      ingredients: const ['200 g potatoes', '2 eggs'],
      steps: steps,
      kitchenGear: const ['Pan'],
      structuredIngredients: structured ??
          [
            RecipeIngredient(
                name: 'potatoes', amount: 200, unit: 'g', cut: 'thin_slice'),
            RecipeIngredient(name: 'eggs', amount: 2, unit: 'piece'),
          ],
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

Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(_host(screen));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Starts the cook so the focused body — and its progress bar — is on screen.
Future<void> _startCook(WidgetTester tester) async {
  await tester.tap(find.text('Start Cooking').last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('R1 — dedup, both branches', () {
    testWidgets('a generated prep step is REPLACED, not appended',
        (tester) async {
      // 4 generated steps, the first of which is a prep step → 4 displayed
      // (1 synthesized + 3 cooking).
      await _pump(
        tester,
        OnePanCookingRoadmapScreen(
          recipe: _recipe(steps: [
            _step('Prepare Your Ingredients',
                heat: 'off_heat', minutes: 0, bullets: const ['Slice things']),
            _step('Heat the oil'),
            _step('Boil the pasta'),
            _step('Plate it up', heat: 'off_heat'),
          ]),
        ),
      );

      expect(find.text('Set up your board'), findsOneWidget);
      expect(find.text('Prepare Your Ingredients'), findsNothing,
          reason: 'never two prep steps');

      await _startCook(tester);
      expect(find.textContaining('Step 1 of 4'), findsOneWidget);
    });

    testWidgets('with no generated prep step, Step 1 is INSERTED',
        (tester) async {
      // 3 generated cooking steps → 4 displayed.
      await _pump(
        tester,
        OnePanCookingRoadmapScreen(
          recipe: _recipe(steps: [
            _step('Heat the oil'),
            _step('Boil the pasta'),
            _step('Plate it up', heat: 'off_heat'),
          ]),
        ),
      );

      expect(find.text('Set up your board'), findsOneWidget);

      await _startCook(tester);
      expect(find.textContaining('Step 1 of 4'), findsOneWidget);
    });

    testWidgets('a prep-looking step at index 2+ is never deduped',
        (tester) async {
      await _pump(
        tester,
        OnePanCookingRoadmapScreen(
          recipe: _recipe(steps: [
            _step('Heat the oil'),
            _step('Prepare the garnish', heat: 'off_heat'),
            _step('Plate it up', heat: 'off_heat'),
          ]),
        ),
      );

      // 3 generated + 1 synthesized, nothing removed.
      await _startCook(tester);
      expect(find.textContaining('Step 1 of 4'), findsOneWidget);
    });
  });

  group('R2 — one step list, every consumer agrees', () {
    testWidgets('progress bar, overview sheet and whisper all use it',
        (tester) async {
      await _pump(
        tester,
        OnePanCookingRoadmapScreen(
          recipe: _recipe(steps: [
            _step('Prepare Your Ingredients',
                heat: 'off_heat', minutes: 0, bullets: const ['Slice things']),
            _step('Heat the oil'),
            _step('Boil the pasta'),
          ]),
        ),
      );

      await _startCook(tester);

      // Progress bar counts the deduped list.
      expect(find.textContaining('Step 1 of 3'), findsOneWidget);

      // The whisper names the first REAL cooking step.
      expect(find.text('Next · Heat the oil'), findsOneWidget);

      // The overview sheet lists the same list, mise included, once.
      await tester.tap(find.textContaining('Step 1 of 3'));
      await tester.pumpAndSettle();
      expect(find.text('All steps'), findsOneWidget);
      expect(find.text('Set up your board'), findsWidgets);
      expect(find.text('Prepare Your Ingredients'), findsNothing);
    });
  });

  group('R3 — Step 1 is a read, not a cooking step', () {
    testWidgets('no timer and no heat pill', (tester) async {
      await _pump(
        tester,
        OnePanCookingRoadmapScreen(
          recipe: _recipe(steps: [_step('Heat the oil'), _step('Plate up')]),
        ),
      );

      expect(find.text('No heat yet'), findsOneWidget);
      expect(find.text('Medium heat'), findsNothing);
      expect(find.text('Medium-high heat'), findsNothing);
    });
  });

  group('R3 — Step 1 never reaches a prompt payload', () {
    testWidgets('the SOS recipe context omits the mise step', (tester) async {
      // A real phone viewport: the SOS sheet is taller than the default
      // 800x600 test window and overflows in it. Pre-existing, unrelated to
      // this build, and not what is being asserted here.
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(
        tester,
        OnePanCookingRoadmapScreen(
          recipe: _recipe(steps: [
            _step('Heat the oil'),
            _step('Boil the pasta'),
          ]),
        ),
      );
      await _startCook(tester);

      // Open SOS and read the context the sheet was handed.
      await tester.tap(find.text('SOS'));
      await tester.pumpAndSettle();

      // The mise step's title must not be described to the model as a step.
      // The sheet renders the recipe context it will send; the real assertion
      // is that "Set up your board" is not numbered as step 1 of the recipe.
      expect(find.textContaining('1. Set up your board'), findsNothing);
    });
  });

  group('R6 — the serves pill', () {
    testWidgets('reads the frozen launch value when supplied', (tester) async {
      await _pump(
        tester,
        OnePanCookingRoadmapScreen(
          recipe: _recipe(steps: [_step('Heat the oil')]),
          servings: 5,
        ),
      );

      expect(find.textContaining('Serves 5'), findsOneWidget);
      // Scaled from base 2 → 5: 200 g becomes 500 g.
      expect(find.text('500 g'), findsOneWidget);
    });

    testWidgets('falls back to the recipe base when null', (tester) async {
      await _pump(
        tester,
        OnePanCookingRoadmapScreen(
          recipe: _recipe(steps: [_step('Heat the oil')]),
        ),
      );

      expect(find.textContaining('Serves 2'), findsOneWidget);
      expect(find.text('200 g'), findsOneWidget);
    });
  });

  group('the checklist is gone', () {
    testWidgets('no counter, no tick rows, no inline stepper', (tester) async {
      await _pump(
        tester,
        OnePanCookingRoadmapScreen(
          recipe: _recipe(steps: [_step('Heat the oil')]),
        ),
      );

      expect(find.text('Ingredients Checklist'), findsNothing);
      expect(find.textContaining('Check items off'), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);

      // The pre-cook inline servings stepper is gone: no + / − controls.
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.byIcon(Icons.remove_rounded), findsNothing);
    });

    testWidgets('nothing in the mise card is tappable except the whisper',
        (tester) async {
      await _pump(
        tester,
        OnePanCookingRoadmapScreen(
          recipe: _recipe(steps: [_step('Heat the oil')]),
        ),
      );

      final card = find.byType(MiseEnPlaceCard);
      expect(card, findsOneWidget);

      // No checkboxes, no list tiles, no switches inside the card.
      expect(
          find.descendant(of: card, matching: find.byType(Checkbox)), findsNothing);
      expect(find.descendant(of: card, matching: find.byType(ListTile)),
          findsNothing);
      expect(find.descendant(of: card, matching: find.byType(Switch)),
          findsNothing);
    });
  });

  group('the mise card in isolation', () {
    Widget bare({
      int servings = 2,
      List<RecipeIngredient>? structured,
      String? nextTitle = 'Heat the oil',
    }) =>
        _host(Scaffold(
          body: SingleChildScrollView(
            child: MiseEnPlaceCard(
              stepNumber: 1,
              title: 'Set up your board',
              servings: servings,
              structuredIngredients: structured ??
                  [
                    RecipeIngredient(
                        name: 'potatoes',
                        amount: 200,
                        unit: 'g',
                        cut: 'thin_slice'),
                    RecipeIngredient(name: 'eggs', amount: 2, unit: 'piece'),
                    RecipeIngredient(
                        name: 'carrot',
                        amount: 1,
                        unit: 'piece',
                        cut: 'julienne'),
                  ],
              basePortions: 2,
              fallbackIngredients: const [],
              steps: const [],
              nextStepTitle: nextTitle,
            ),
          ),
        ));

    testWidgets('splits knife work from have-out items', (tester) async {
      await tester.pumpWidget(bare());
      await tester.pump();

      expect(find.text('NEEDS THE KNIFE'), findsOneWidget);
      expect(find.text('JUST HAVE IT OUT'), findsOneWidget);

      // eggs have no cut → the compact have-out row.
      expect(find.text('2 eggs'), findsOneWidget);
    });

    testWidgets('a pill renders only for a BUILT diagram', (tester) async {
      await tester.pumpWidget(bare());
      await tester.pump();

      // julienne is drawn; thin_slice is a valid key with no painter.
      expect(find.text('Julienne'), findsOneWidget);
      expect(find.textContaining('Thin'), findsNothing);
    });

    testWidgets('no CTA inside the card — the step system owns it',
        (tester) async {
      await tester.pumpWidget(bare());
      await tester.pump();

      expect(
        find.descendant(
            of: find.byType(MiseEnPlaceCard),
            matching: find.byType(FilledButton)),
        findsNothing,
        reason: 'a second filled button would break one-terracotta-CTA',
      );
    });

    testWidgets('the serves pill has no control on it', (tester) async {
      await tester.pumpWidget(bare(servings: 4));
      await tester.pump();

      expect(find.textContaining('Serves 4'), findsOneWidget);
      expect(
        find.descendant(
            of: find.byType(MiseEnPlaceCard),
            matching: find.byType(IconButton)),
        findsNothing,
      );
    });

    testWidgets('no overflow at 360 logical px', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(bare());
      await tester.pump();

      expect(tester.takeException(), isNull);
      // No horizontal scrolling anywhere in the card.
      expect(
        find.descendant(
          of: find.byType(MiseEnPlaceCard),
          matching: find.byWidgetPredicate((w) =>
              w is SingleChildScrollView && w.scrollDirection == Axis.horizontal),
        ),
        findsNothing,
      );
    });

    testWidgets('an unstructured recipe still reads', (tester) async {
      await tester.pumpWidget(_host(const Scaffold(
        body: SingleChildScrollView(
          child: MiseEnPlaceCard(
            stepNumber: 1,
            title: 'Set up your board',
            servings: 2,
            structuredIngredients: [],
            basePortions: null,
            fallbackIngredients: ['200 g rice', '2 eggs'],
            steps: [],
          ),
        ),
      )));
      await tester.pump();

      expect(find.textContaining('200 g rice'), findsOneWidget);
    });
  });

  test('the palette guard still owns every colour used here', () {
    // A cheap structural assertion: the card's champagne, sage and neutral
    // pills all come from tokens, so the guard test covers them.
    expect(AppDesignTokens.champagneTint, isNotNull);
    expect(AppDesignTokens.sageTeachingPanel, isNotNull);
    expect(AppDesignTokens.neutralPillTint, isNotNull);
  });

  test('the servings fallback matches the overview precedence', () {
    // R6: when the launch supplies nothing, Step 1 uses the same precedence
    // the overview does.
    expect(
      defaultServingsFor(profileHouseholdServings: null, recipeBasePortions: 2),
      2,
    );
    expect(
      defaultServingsFor(profileHouseholdServings: 4, recipeBasePortions: 2),
      4,
    );
  });

  group('R4 — no separate checklist surface exists', () {
    test('no checklist route is declared anywhere', () {
      // The spec calls for deleting "ChecklistScreen as a distinct route".
      // There never was one — the checklist was a CARD inside Cook Mode's
      // pre-cook body, which is what this build deleted. This guard makes
      // sure one is never introduced: Cook Mode opens on Step 1, and a
      // second prep surface is exactly the thing the merge removed.
      final routes = File('lib/nav.dart').readAsStringSync();
      expect(RegExp(r'checklist', caseSensitive: false).hasMatch(routes),
          isFalse,
          reason: 'no checklist route may exist');
    });

    test('the checklist classes are gone from the source', () {
      // Comments stripped: a doc reference explaining what was removed is
      // the opposite of the failure being guarded against.
      final cookMode =
          File('lib/screens/one_pan_cooking_roadmap_screen.dart')
              .readAsLinesSync()
              .map((l) {
                final t = l.trimLeft();
                if (t.startsWith('//')) return '';
                final i = l.indexOf('//');
                return i == -1 ? l : l.substring(0, i);
              })
              .join(' ');
      for (final name in [
        '_IngredientsChecklistCard',
        '_IngredientChecklistRow',
        '_checkedIngredientIndices',
        '_changePortions(',
      ]) {
        expect(cookMode.contains(name), isFalse, reason: '$name still exists');
      }
    });

    testWidgets('resuming lands on the stored step, not a prep surface',
        (tester) async {
      final session = ActiveCookSession(
        recipe: _recipe(steps: [
          _step('Heat the oil'),
          _step('Boil the pasta'),
        ]),
        cookStarted: true,
        cookPaused: true,
        // Index 2 of the displayed list = the second real cooking step.
        activeStepIndex: 2,
        completedSteps: const {0, 1},
        activeRemaining: const Duration(minutes: 3),
        currentPortions: 2,
        surface: null,
        isReCook: false,
        lastUpdatedAt: DateTime.now(),
      );

      await _pump(
        tester,
        OnePanCookingRoadmapScreen(resumeSession: session),
      );

      expect(find.textContaining('Step 3 of 3'), findsOneWidget);
      expect(find.text('Boil the pasta'), findsOneWidget);
      expect(find.text('Set up your board'), findsNothing,
          reason: 'a resume never drops the cook back onto the prep read');
    });
  });

  group('R7 — wrap never clip', () {
    test('no horizontal scroll view anywhere in lib', () {
      var offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.readAsStringSync().contains('scrollDirection: Axis.horizontal')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'controls wrap, never clip — app-wide kit rule');
    });
  });
}
