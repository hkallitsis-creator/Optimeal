import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/data/sensory_cue_vocabulary.dart';
import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/user_profile_service.dart';
import 'package:optimeal/state/ingredient_prep_controller.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme/app_design_tokens.dart';

/// Cook Mode Unit B (2026-08-22): the focused, one-step-dominant layout.
///
/// These drive the real screen. Everything asserted here is composition and
/// navigation — nothing touches the Waste Ledger or Supabase, because nothing
/// in this layout depends on them.

/// A recipe whose steps carry real declared cue keys, so the cue panel is
/// exercised against the live data contract rather than a stub.
///
/// `oil_shimmers` is a **readiness** cue with both remedies; `fork_slides_easily`
/// is a **doneness** cue; the third step declares `no_cue`, which must render
/// no panel at all.
CookModeRecipePayload _recipe() => const CookModeRecipePayload(
      title: 'Zucchini Skillet',
      ingredients: ['300g Zucchini', '100g Feta', '2 tbsp Olive oil'],
      basePortions: 2,
      steps: [
        CookModeStepPayload(
          title: 'Heat the oil',
          heat: 'medium_high',
          durationMinutes: 3,
          bullets: ['Use a wide pan.', 'Do not crowd it.'],
          sensoryCue: 'oil_shimmers',
        ),
        CookModeStepPayload(
          title: 'Boil the pasta',
          heat: 'medium',
          durationMinutes: 9,
          bullets: ['Salt the water well.'],
          sensoryCue: 'fork_slides_easily',
        ),
        CookModeStepPayload(
          title: 'Plate it up',
          heat: 'off_heat',
          durationMinutes: 2,
          bullets: ['Crumble the feta over the top.'],
        ),
      ],
    );

Widget _wrap(CookModeRecipePayload recipe) {
  final router = GoRouter(
    initialLocation: '/cook',
    routes: [
      GoRoute(
        path: '/cook',
        builder: (context, state) =>
            OnePanCookingRoadmapScreen(recipe: recipe, surface: null),
      ),
      GoRoute(
          path: AppRoutes.home,
          builder: (c, s) => const Scaffold(body: Text('home'))),
    ],
  );

  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => IngredientPrepController()),
      ChangeNotifierProvider(
          create: (_) => UserProfileController(UserProfileService())),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Pumps Cook Mode and presses Start, so every test below lands in the
/// focused layout — which is the state Unit B specifies. The pre-cook body is
/// a separate queued build and deliberately untouched.
Future<void> _pumpCooking(WidgetTester tester,
    {CookModeRecipePayload? recipe}) async {
  tester.view.physicalSize = const Size(600, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_wrap(recipe ?? _recipe()));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Start Cooking').last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Advances past the synthesized, timerless mise-en-place step that Cook Mode
/// prepends to every recipe. Its CTA is the bottom bar's Next, relabelled.
Future<void> _nextStep(WidgetTester tester) async {
  final mise = find.text("Board's clear — heat goes on");
  await tester.tap(mise.evaluate().isNotEmpty ? mise : find.text('Next step'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('composition', () {
    testWidgets('header, progress bar, one step card, whisper and bottom bar',
        (tester) async {
      await _pumpCooking(tester);

      // Header: title + the persistent SOS square.
      expect(find.text('Cook mode'), findsOneWidget);
      expect(find.text('SOS'), findsOneWidget);

      // Progress: "Step N of M · title".
      expect(find.textContaining('Step 1 of 4'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // One step card only — the old all-steps list is gone, so a later
      // step's title must not be on screen as a card.
      // Step 1 is the mise card — no longer an ordinary step card.
      expect(find.text('Set up your board'), findsOneWidget);
      expect(find.text('Boil the pasta'), findsNothing);

      // Whisper (the mise card carries its own).
      expect(find.textContaining('Next · '), findsOneWidget);

      // Bottom bar — relabelled on Step 1.
      expect(find.text("Board's clear — heat goes on"), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.textContaining('Stuck?'), findsOneWidget);
    });

    testWidgets('exactly one terracotta CTA on screen', (tester) async {
      await _pumpCooking(tester);

      final filled = tester.widgetList<FilledButton>(find.byType(FilledButton));
      expect(filled, hasLength(1),
          reason: 'the only filled button is "Next step"');

      // The pause control is an outlined square, not a second filled button.
      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    testWidgets('Finish & Plate is never on the step screen', (tester) async {
      await _pumpCooking(tester);
      expect(find.text('Finish & Plate'), findsNothing);

      await _nextStep(tester);
      expect(find.text('Finish & Plate'), findsNothing);
    });

    testWidgets('the heat pill is the only warm pill on the card',
        (tester) async {
      await _pumpCooking(tester);
      await _nextStep(tester);

      expect(find.text('Heat the oil'), findsOneWidget);
      expect(find.text('Medium-high heat'), findsOneWidget);
      expect(find.text('~3 min'), findsOneWidget);

      final champagnePills = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).color ==
                  AppDesignTokens.champagneTint);
      // One: the heat pill. (The SOS square uses a Material, not a Container
      // fill, so it does not double-count here.)
      expect(champagnePills, hasLength(1));
    });
  });

  group('the next-step whisper', () {
    testWidgets('names the step that is actually next', (tester) async {
      await _pumpCooking(tester);

      // On the mise step, next is step 1 of the recipe proper. The mise
      // card's whisper prefixes it, so match on the combined line.
      expect(find.text('Next · Heat the oil'), findsOneWidget,
          reason: 'shown only as the whisper line, not as a card');

      await _nextStep(tester);
      expect(find.text('Boil the pasta'), findsOneWidget);
    });

    testWidgets('tapping it opens the overview sheet', (tester) async {
      await _pumpCooking(tester);

      await tester.tap(find.text('Next · Heat the oil'));
      await tester.pumpAndSettle();

      expect(find.text('All steps'), findsOneWidget);
      expect(find.text('Finish & Plate'), findsOneWidget);
    });

    testWidgets('the last step has no whisper', (tester) async {
      await _pumpCooking(tester);
      await _nextStep(tester);
      await _nextStep(tester);
      await _nextStep(tester);

      expect(find.text('Plate it up'), findsOneWidget);
      expect(find.textContaining('Step 4 of 4'), findsOneWidget);
      // Deliberate asymmetry: no previous-step whisper either.
      expect(find.text('NEXT'), findsNothing);
    });
  });

  group('the cue panel', () {
    testWidgets('a readiness cue gets the readiness label', (tester) async {
      await _pumpCooking(tester);
      await _nextStep(tester);

      expect(find.text('HOW YOU KNOW IT\'S RIGHT'), findsOneWidget);
      expect(find.text('HOW YOU KNOW IT\'S DONE'), findsNothing);
      // The signed sentence, rendered from the vocabulary — not invented here.
      expect(
        find.text(SensoryCueVocabulary.byKey('oil_shimmers')!.harrisSays),
        findsOneWidget,
      );
    });

    testWidgets('a doneness cue gets the doneness label', (tester) async {
      await _pumpCooking(tester);
      await _nextStep(tester);
      await _nextStep(tester);

      expect(find.text('HOW YOU KNOW IT\'S DONE'), findsOneWidget);
      expect(find.text('HOW YOU KNOW IT\'S RIGHT'), findsNothing);
    });

    testWidgets('the remedy expander opens inline, without a sheet',
        (tester) async {
      await _pumpCooking(tester);
      await _nextStep(tester);

      expect(find.text('Not there yet'), findsNothing);

      await tester.tap(find.text('Not there yet, or gone too far?'));
      await tester.pumpAndSettle();

      expect(find.text('Not there yet'), findsOneWidget);
      expect(find.text('Gone too far'), findsOneWidget);
      // Inline — the step card is still on screen behind nothing at all.
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Heat the oil'), findsOneWidget);
    });

    testWidgets('a step with no cue shows no panel and no empty frame',
        (tester) async {
      await _pumpCooking(tester);
      await _nextStep(tester);
      await _nextStep(tester);
      await _nextStep(tester);

      expect(find.text('Plate it up'), findsOneWidget);
      expect(find.textContaining('HOW YOU KNOW'), findsNothing);
      expect(find.text('Not there yet, or gone too far?'), findsNothing);
    });
  });

  group('the overview sheet', () {
    testWidgets('opens from the progress bar and lists every step',
        (tester) async {
      await _pumpCooking(tester);

      await tester.tap(find.textContaining('Step 1 of 4'));
      await tester.pumpAndSettle();

      expect(find.text('All steps'), findsOneWidget);
      for (final title in [
        'Set up your board',
        'Heat the oil',
        'Boil the pasta',
        'Plate it up',
      ]) {
        expect(find.text(title), findsWidgets, reason: title);
      }
    });

    testWidgets('panes swap in place — a second sheet is never stacked',
        (tester) async {
      await _pumpCooking(tester);
      // Past the prep step first: its bullets ARE the ingredient names, so
      // staying on it would make "is this ingredient on screen?" ambiguous.
      await _nextStep(tester);
      await tester.tap(find.textContaining('Step 2 of 4'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);

      await tester.tap(find.text('Ingredients'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget,
          reason: 'still exactly one sheet');
      expect(find.text('All steps'), findsNothing);
      expect(find.text('300g Zucchini'), findsOneWidget);
      expect(find.text('For 2 servings'), findsNothing,
          reason: 'this recipe has no structured ingredients to scale');

      // Back returns to pane 1 rather than closing.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('All steps'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('the ingredients pane answers "how much X" with quantities',
        (tester) async {
      await _pumpCooking(tester);
      await _nextStep(tester);
      await tester.tap(find.textContaining('Step 2 of 4'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ingredients'));
      await tester.pumpAndSettle();

      expect(find.text('300g Zucchini'), findsOneWidget);
      expect(find.text('100g Feta'), findsOneWidget);
      expect(find.text('2 tbsp Olive oil'), findsOneWidget);
    });

    testWidgets('tapping an upcoming step jumps the cook to it',
        (tester) async {
      await _pumpCooking(tester);
      await tester.tap(find.textContaining('Step 1 of 4'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Boil the pasta').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Step 3 of 4'), findsOneWidget);
      expect(find.text('HOW YOU KNOW IT\'S DONE'), findsOneWidget);
      // The jumped-past steps read as done, so the whisper is now step 4.
      expect(find.text('Plate it up'), findsOneWidget);
    });

    testWidgets('Finish & Plate sits at the end of the list, once',
        (tester) async {
      await _pumpCooking(tester);
      await tester.tap(find.textContaining('Step 1 of 4'));
      await tester.pumpAndSettle();

      expect(find.text('Finish & Plate'), findsOneWidget);

      // And it is the last thing in the list, below every step row.
      final finishY =
          tester.getTopLeft(find.text('Finish & Plate')).dy;
      final lastStepY = tester.getTopLeft(find.text('Plate it up').last).dy;
      expect(finishY, greaterThan(lastStepY));
    });
  });

  group('the SOS square', () {
    testWidgets('is present before the cook starts and during it',
        (tester) async {
      tester.view.physicalSize = const Size(600, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(_recipe()));
      await tester.pumpAndSettle();
      expect(find.text('SOS'), findsOneWidget,
          reason: 'findable before Start too');

      await tester.tap(find.text('Start Cooking').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('SOS'), findsOneWidget);
    });
  });
}
