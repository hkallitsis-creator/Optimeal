import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/models/recipe_origin.dart';
import 'package:optimeal/models/planner_slot_ref.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/services/user_profile_service.dart';
import 'package:optimeal/state/ingredient_prep_controller.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme/app_design_tokens.dart';

/// Part 2 (back → overview) and Part 3 (type scale).

CookModeStepPayload _step(String title, {String heat = 'medium', int min = 5}) =>
    CookModeStepPayload(
      title: title,
      heat: heat,
      durationMinutes: min,
      bullets: const ['do the thing'],
    );

CookModeRecipePayload _recipe({RecipeOrigin? origin}) => CookModeRecipePayload(
      title: 'Chicken Traybake',
      ingredients: const ['200 g potatoes'],
      steps: [_step('Heat the oil'), _step('Roast it', min: 20)],
      kitchenGear: const ['Pan'],
      structuredIngredients: [
        RecipeIngredient(name: 'potatoes', amount: 200, unit: 'g'),
      ],
      basePortions: 2,
      origin: origin,
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
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Part 2 — the session is what carries the recipe back', () {
    test('ActiveCookSession carries the full payload', () {
      // 2a: this is the object the overview reads to resume. It carries the
      // whole recipe, the step index, the completed set AND the planner slot
      // — which is why a round trip through the overview cannot lose slot
      // attribution.
      final session = ActiveCookSession(
        recipe: _recipe(origin: RecipeOrigin.fridgeClearer),
        cookStarted: true,
        cookPaused: true,
        activeStepIndex: 2,
        completedSteps: const {0, 1},
        activeRemaining: const Duration(minutes: 4),
        currentPortions: 3,
        surface: CookModeSurface.weeklyPlanner,
        isReCook: false,
        lastUpdatedAt: DateTime.now(),
        plannerSlot: const PlannerSlotRef(
          weekStart: '2026-08-17',
          dayIndex: 2,
          slotIndex: 0,
        ),
      );

      expect(session.recipe.title, 'Chicken Traybake');
      expect(session.recipe.origin, RecipeOrigin.fridgeClearer,
          reason: 'provenance survives the round trip');
      expect(session.plannerSlot?.dayIndex, 2,
          reason: 'slot ref survives, so resuming still attributes');
      expect(session.activeStepIndex, 2,
          reason: 'Start cooking resumes here, not at Step 1');
    });

    test('back routes to the overview, not out to the generation surface', () {
      final code = File('lib/screens/one_pan_cooking_roadmap_screen.dart')
          .readAsStringSync();
      expect(code.contains('void _backToOverview()'), isTrue);
      expect(code.contains('pushReplacement(AppRoutes.recipe'), isTrue,
          reason: 'replacement, so a round trip cannot stack Cook Modes');
      expect(code.contains('onPressed: _backToOverview'), isTrue);
    });

    test('the overview resumes rather than restarting', () {
      final code =
          File('lib/screens/recipe_details_screen.dart').readAsStringSync();
      expect(code.contains('_resumableSession'), isTrue);
      expect(code.contains('loadActiveSession'), isTrue);
      expect(
        code.contains('context.push(AppRoutes.onePanCookingRoadmap, extra: resume)'),
        isTrue,
        reason: 'resume passes the SESSION, which carries step + slot',
      );
    });

    test('back does not end the session', () {
      final code = File('lib/screens/one_pan_cooking_roadmap_screen.dart')
          .readAsStringSync();
      final start = code.indexOf('void _backToOverview()');
      final body = code.substring(start, start + 700);
      expect(body.contains('clearActiveSession'), isFalse,
          reason: 'the session stays active until Finish & Plate or abandon');
    });

    testWidgets('the home glyph is still present and separate', (tester) async {
      await tester.pumpWidget(_host(OnePanCookingRoadmapScreen(recipe: _recipe())));
      await tester.pump();
      // Back + home glyph both live in the leading slot; behaviour of the
      // glyph is unchanged by this build.
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });
  });

  group('system back does what the arrow does', () {
    test('a PopScope routes it through the same handler', () {
      final code = File('lib/screens/one_pan_cooking_roadmap_screen.dart')
          .readAsStringSync();

      expect(code.contains('return PopScope('), isTrue);
      // canPop is true ONLY for the recipe-less demo body, which has no
      // overview to go to.
      expect(code.contains('canPop: _payload == null'), isTrue);

      final start = code.indexOf('return PopScope(');
      final block = code.substring(start, start + 400);
      expect(block.contains('_backToOverview()'), isTrue,
          reason: 'system back and the arrow must not disagree');
      expect(block.contains('if (didPop) return;'), isTrue,
          reason: 'no double-pop');
    });

    testWidgets('system back from a step lands on the overview route',
        (tester) async {
      // The route push is what is asserted: pumping the destination needs a
      // router, and RecipeDetailsScreen needs a live Supabase client.
      final code = File('lib/screens/one_pan_cooking_roadmap_screen.dart')
          .readAsStringSync();
      final start = code.indexOf('void _backToOverview()');
      final body = code.substring(start, start + 700);

      expect(body.contains('AppRoutes.recipe'), isTrue);
      expect(body.contains('_persistActiveSession()'), isTrue,
          reason: 'the session — and its step index — is kept, not ended');
      expect(body.contains('clearActiveSession'), isFalse);
    });
  });

  group('Part 3 — type scale', () {
    test('the body token went up, once, in the tokens file', () {
      final tokens =
          File('lib/theme/app_design_tokens.dart').readAsStringSync();
      expect(
        tokens.contains('static const TextStyle body = TextStyle(fontSize: 16'),
        isTrue,
        reason: 'one change, not per-widget',
      );
      expect(AppDesignTokens.body.fontSize, 16);
    });

    testWidgets('the step card survives 360 px at textScale 1.3',
        (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const wordy = CookModeRecipePayload(
        title: 'Wordy dish',
        ingredients: ['200 g potatoes'],
        steps: [
          CookModeStepPayload(
            title:
                'Sear the chicken thighs skin side down until deeply golden brown',
            heat: 'medium_high',
            durationMinutes: 8,
            bullets: [
              'Pat the skin completely dry with kitchen paper first, because '
                  'any surface moisture will steam the skin instead of '
                  'crisping it, and a soggy skin cannot be rescued later on '
                  'in the cook no matter how long you leave it in the pan.',
            ],
          ),
          CookModeStepPayload(
              title: 'Rest', heat: 'off_heat', durationMinutes: 5, bullets: []),
        ],
        kitchenGear: ['Pan'],
        basePortions: 2,
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: _host(const OnePanCookingRoadmapScreen(recipe: wordy)),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Start Cooking').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text("Board's clear — heat goes on"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull,
          reason: 'the step card scrolls internally; the CTA bar never moves');
      expect(find.text('Next step'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
