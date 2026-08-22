import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/user_profile_service.dart';
import 'package:optimeal/state/ingredient_prep_controller.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/widgets/step_timer_pill.dart';

/// Timer semantics (Harris, 23 Aug).
///
/// What this replaced: the timer started by itself on step entry and
/// **advanced the step** when it hit zero. Neither was in the signed spec.
/// The pan is the authority on doneness, not the estimate on the card.

CookModeStepPayload _step(
  String title, {
  String heat = 'medium',
  int minutes = 5,
}) =>
    CookModeStepPayload(
      title: title,
      heat: heat,
      durationMinutes: minutes,
      bullets: const ['do the thing'],
    );

CookModeRecipePayload _recipe({List<CookModeStepPayload>? steps}) =>
    CookModeRecipePayload(
      title: 'Test dish',
      ingredients: const ['200 g potatoes'],
      steps: steps ??
          [
            _step('Heat the oil', minutes: 3),
            _step('Boil the pasta', minutes: 8),
            _step('Plate it up', heat: 'off_heat', minutes: 2),
          ],
      kitchenGear: const ['Pan'],
      structuredIngredients: [
        RecipeIngredient(name: 'potatoes', amount: 200, unit: 'g'),
      ],
      basePortions: 2,
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

Future<void> _pumpCooking(WidgetTester tester,
    {CookModeRecipePayload? recipe}) async {
  await tester.pumpWidget(
      _host(OnePanCookingRoadmapScreen(recipe: recipe ?? _recipe())));
  await tester.pump();
  await tester.tap(find.text('Start Cooking').last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Past the mise step, onto the first real cooking step.
Future<void> _toFirstCookingStep(WidgetTester tester) async {
  await tester.tap(find.text("Board's clear — heat goes on"));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

StepTimerPill _pill(WidgetTester tester) =>
    tester.widget<StepTimerPill>(find.byType(StepTimerPill));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('idle is the resting state', () {
    testWidgets('a step opens IDLE with nothing counting', (tester) async {
      await _pumpCooking(tester);
      await _toFirstCookingStep(tester);

      expect(_pill(tester).state, StepTimerState.idle);
      expect(find.text('3 min'), findsOneWidget);

      // Three seconds of wall clock later, still three minutes.
      await tester.pump(const Duration(seconds: 3));
      expect(_pill(tester).state, StepTimerState.idle);
      expect(find.text('3 min'), findsOneWidget);
    });

    testWidgets('Step 1 (mise) has no timer pill at all', (tester) async {
      await _pumpCooking(tester);
      expect(find.byType(StepTimerPill), findsNothing);
    });

    testWidgets('advancing to a new step lands IDLE again', (tester) async {
      await _pumpCooking(tester);
      await _toFirstCookingStep(tester);

      await tester.tap(find.byType(StepTimerPill));
      await tester.pump();
      expect(_pill(tester).state, StepTimerState.running);

      await tester.tap(find.text('Next step'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(_pill(tester).state, StepTimerState.idle,
          reason: 'a step change cancels a running timer and resets to idle');
      expect(find.text('8 min'), findsOneWidget);
    });
  });

  group('tap to start, tap to pause', () {
    testWidgets('tapping starts the countdown', (tester) async {
      await _pumpCooking(tester);
      await _toFirstCookingStep(tester);

      await tester.tap(find.byType(StepTimerPill));
      await tester.pump();
      expect(_pill(tester).state, StepTimerState.running);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('02:58'), findsOneWidget);
    });

    testWidgets('tapping again pauses, and again resumes', (tester) async {
      await _pumpCooking(tester);
      await _toFirstCookingStep(tester);

      await tester.tap(find.byType(StepTimerPill));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byType(StepTimerPill));
      await tester.pump();
      expect(_pill(tester).state, StepTimerState.paused);

      // Paused means paused: the clock does not move.
      await tester.pump(const Duration(seconds: 5));
      expect(_pill(tester).state, StepTimerState.paused);
      expect(find.textContaining('02:58'), findsOneWidget);

      await tester.tap(find.byType(StepTimerPill));
      await tester.pump();
      expect(_pill(tester).state, StepTimerState.running);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the ± adjusters', () {
    testWidgets('work while idle, with a one-minute floor', (tester) async {
      await _pumpCooking(tester);
      await _toFirstCookingStep(tester);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      expect(find.text('4 min'), findsOneWidget);

      for (var i = 0; i < 10; i++) {
        await tester.tap(find.byIcon(Icons.remove_rounded));
        await tester.pump();
      }
      expect(find.text('1 min'), findsOneWidget,
          reason: 'floor is one minute, never zero');
    });

    testWidgets('are hidden while running, and back when paused',
        (tester) async {
      await _pumpCooking(tester);
      await _toFirstCookingStep(tester);

      await tester.tap(find.byType(StepTimerPill));
      await tester.pump();
      expect(find.byIcon(Icons.add_rounded), findsNothing,
          reason: 'a greyed control mid-cook reads as broken; hide it');

      await tester.tap(find.byType(StepTimerPill));
      await tester.pump();
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('zero — announce, then wait', () {
    testWidgets('the step does NOT change, ever', (tester) async {
      await _pumpCooking(
        tester,
        recipe: _recipe(steps: [
          _step('Heat the oil', minutes: 1),
          _step('Boil the pasta', minutes: 8),
        ]),
      );
      await _toFirstCookingStep(tester);

      expect(find.textContaining('Step 2 of 3'), findsOneWidget);

      await tester.tap(find.byType(StepTimerPill));
      await tester.pump();
      await tester.pump(const Duration(seconds: 61));
      await tester.pump(const Duration(milliseconds: 400));

      expect(_pill(tester).state, StepTimerState.done);
      expect(find.textContaining('Step 2 of 3'), findsOneWidget,
          reason: 'the step index must be unchanged at zero');
      expect(find.text('Heat the oil'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tapping the done pill stops it without advancing',
        (tester) async {
      await _pumpCooking(
        tester,
        recipe: _recipe(steps: [
          _step('Heat the oil', minutes: 1),
          _step('Boil the pasta', minutes: 8),
        ]),
      );
      await _toFirstCookingStep(tester);

      await tester.tap(find.byType(StepTimerPill));
      await tester.pump();
      await tester.pump(const Duration(seconds: 61));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_pill(tester).state, StepTimerState.done);

      await tester.tap(find.byType(StepTimerPill));
      await tester.pump();

      expect(_pill(tester).state, StepTimerState.idle,
          reason: 'pulse stops');
      expect(find.text('Heat the oil'), findsOneWidget,
          reason: 'and the step stays');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Next clears the done state', (tester) async {
      await _pumpCooking(
        tester,
        recipe: _recipe(steps: [
          _step('Heat the oil', minutes: 1),
          _step('Boil the pasta', minutes: 8),
        ]),
      );
      await _toFirstCookingStep(tester);

      await tester.tap(find.byType(StepTimerPill));
      await tester.pump();
      await tester.pump(const Duration(seconds: 61));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('Next step'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(_pill(tester).state, StepTimerState.idle);
      expect(find.text('Boil the pasta'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the auto paths are gone, and stay gone', () {
    test('no auto-start or auto-advance survives in the source', () {
      final code = File('lib/screens/one_pan_cooking_roadmap_screen.dart')
          .readAsLinesSync()
          .map((l) {
            final t = l.trimLeft();
            if (t.startsWith('//')) return '';
            final i = l.indexOf('//');
            return i == -1 ? l : l.substring(0, i);
          })
          .join('\n');

      // The old method that auto-started on every step entry.
      expect(code.contains('_resumeTimer'), isFalse,
          reason: 'auto-start on step entry must not come back');

      // The timer-done handler must not advance or complete the step.
      final start = code.indexOf('Future<void> _onActiveTimerDone');
      expect(start, greaterThan(0));
      final body = code.substring(start, code.indexOf('void _advanceToNextStep'));
      expect(body.contains('_advanceToNextStep'), isFalse,
          reason: 'zero must never move the cook on');
      expect(body.contains('_completedSteps'), isFalse,
          reason: 'zero must never mark the step done for the user');
    });
  });

  group('the pill in isolation', () {
    testWidgets('renders each state distinctly', (tester) async {
      for (final state in StepTimerState.values) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: StepTimerPill(
                state: state,
                remaining: const Duration(minutes: 3),
                onTap: () {},
                onAdjust: (_) {},
              ),
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: state.name);
      }
      await tester.pumpWidget(const SizedBox());
    });
  });
}
