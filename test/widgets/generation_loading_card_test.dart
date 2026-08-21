import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/widgets/generation_loading_card.dart';

/// The one loading card, shown at every AI generation point (2026-08-22).
///
/// The behavioural difference between the two stages is the whole reason it is
/// one parameterized component: a short wait must not cycle copy, a long wait
/// should. Both are asserted here, along with the signed absence of a progress
/// bar and the four wiring points.

Widget _wrap(Widget child, {bool disableAnimations = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: child),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('finding ideas — the short wait', () {
    testWidgets('shows one static line and does NOT cycle', (tester) async {
      await tester.pumpWidget(
          _wrap(const GenerationLoadingCard(stage: GenerationStage.findingIdeas)));
      await tester.pump();

      expect(find.text(GenerationLoadingCard.findingIdeasLine), findsOneWidget);
      expect(
          find.text(GenerationLoadingCard.findingIdeasSubLine), findsOneWidget);

      // Well past several cycle intervals: the line must be the same one.
      // Cycling copy over a two-second wait flickers, which is why this stage
      // deliberately does not.
      await tester.pump(const Duration(seconds: 9));
      expect(find.text(GenerationLoadingCard.findingIdeasLine), findsOneWidget);

      // And none of the long-wait lines ever appear.
      for (final line in GenerationLoadingCard.writingRecipeLines) {
        expect(find.text(line), findsNothing, reason: line);
      }

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('writing recipe — the long wait', () {
    testWidgets('cycles through the lines', (tester) async {
      await tester.pumpWidget(_wrap(
          const GenerationLoadingCard(stage: GenerationStage.writingRecipe)));
      await tester.pump();

      final first = GenerationLoadingCard.writingRecipeLines.first;
      expect(find.text(first), findsOneWidget);

      // Past one interval, the line has moved on.
      await tester.pump(GenerationLoadingCard.lineInterval);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(first), findsNothing);
      expect(
        find.text(GenerationLoadingCard.writingRecipeLines[1]),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('names the dish being written when given one', (tester) async {
      await tester.pumpWidget(_wrap(const GenerationLoadingCard(
        stage: GenerationStage.writingRecipe,
        subject: 'Zucchini Frittata',
      )));
      await tester.pump();

      // Supersedes the inline "Writing the recipe…" on the tapped idea card:
      // the choice stays visible while the recipe is written.
      expect(find.text('Zucchini Frittata'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('ingredient-aware line names the user\'s own ingredients',
        (tester) async {
      await tester.pumpWidget(_wrap(const GenerationLoadingCard(
        stage: GenerationStage.writingRecipe,
        ingredients: ['Zucchini', 'Eggs', 'Potatoes'],
      )));
      await tester.pump();

      // Truthful: those ingredients really are in the prompt for this call.
      expect(find.textContaining('zucchini'), findsOneWidget);
      expect(find.textContaining('eggs'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('falls back to the generic line with too few ingredients',
        (tester) async {
      await tester.pumpWidget(_wrap(const GenerationLoadingCard(
        stage: GenerationStage.writingRecipe,
        ingredients: ['Zucchini'],
      )));
      await tester.pump();

      expect(find.text(GenerationLoadingCard.writingRecipeLines.first),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('signed constraints', () {
    testWidgets('there is no progress bar, in either mode', (tester) async {
      for (final stage in GenerationStage.values) {
        await tester.pumpWidget(_wrap(GenerationLoadingCard(stage: stage)));
        await tester.pump();

        // Signed: generation time is unpredictable, and a stalling bar is
        // worse than none. The pulsing dots say "alive" and promise nothing.
        expect(find.byType(LinearProgressIndicator), findsNothing,
            reason: '$stage');
        expect(find.byType(CircularProgressIndicator), findsNothing,
            reason: '$stage');

        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('reduced motion stops the animation but keeps the card',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const GenerationLoadingCard(stage: GenerationStage.findingIdeas),
        disableAnimations: true,
      ));
      await tester.pump();

      // If the controller were still running, pumpAndSettle would time out —
      // that it returns is the assertion.
      await tester.pumpAndSettle();
      expect(find.text(GenerationLoadingCard.findingIdeasLine), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });

    test('every cycling line claims work the pipeline actually does', () {
      // The truthfulness rule. These lines are claims about real behaviour, so
      // the words below must not appear: there is no nutrition analysis, no
      // cost calculation, and (roadmap item 1) no safety validation.
      final all = [
        ...GenerationLoadingCard.writingRecipeLines,
        GenerationLoadingCard.writingRecipeSubLine,
        GenerationLoadingCard.findingIdeasLine,
        GenerationLoadingCard.findingIdeasSubLine,
      ].join(' ').toLowerCase();

      for (final forbidden in [
        'nutrition',
        'calorie',
        'macro',
        'allerg',
        'safe',
        'cost',
        'budget',
        'price',
      ]) {
        expect(all, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });

  group('wiring — all four generation points', () {
    // Structural assertions, not widget pumps: three of the four surfaces
    // reach for Supabase/entitlement/usage services on the way into a
    // generation, and the fourth (planner-initiated) is not a screen of its
    // own — it is the other three, reached from the planner. What can be
    // proven here is that each surface mounts the component in the right mode,
    // and that no ad-hoc spinner survived beside it.
    String source(String path) => File(path).readAsStringSync();

    test('Fridge Clearer mounts it for BOTH stages, in the right modes', () {
      final s = source('lib/screens/fridge_clearer_screen.dart');
      expect(s, contains('GenerationLoadingCard('));
      expect(s, contains('GenerationStage.writingRecipe'));
      expect(s, contains('GenerationStage.findingIdeas'));
      // Ingredient-aware, because this surface has the real entered list.
      expect(s, contains('ingredients: chosen == null ? null : _sortedIngredients'));
    });

    test('Custom recipe creation mounts it in writing-recipe mode', () {
      final s = source('lib/widgets/custom_ai_recipe_creator_sheet.dart');
      expect(s,
          contains('GenerationLoadingCard(stage: GenerationStage.writingRecipe)'));
    });

    test('the planner paths are the same two surfaces, not a third', () {
      // The Weekly Planner's two generation entry points push the Fridge
      // Clearer (as a picker) and open the Custom creator sheet — both already
      // covered above. If a third ever appears, this list changes.
      final planner = source('lib/screens/weekly_planner_screen.dart');
      expect(planner, contains('AppRoutes.fridgeClearerPicker'));
      expect(planner, contains('CustomAiRecipeCreatorSheet'));
      expect(planner, isNot(contains('askChefHarris')),
          reason: 'the planner never generates on its own');
    });

    test('no ad-hoc spinner survives on a generation wait', () {
      // Every remaining CircularProgressIndicator in lib/ must be a SAVE or a
      // LOAD, never an AI generation wait. Listed explicitly so a new one has
      // to be justified here.
      const allowed = <String>{
        // Planner: slot write in flight, and the day-card saving row.
        'lib/screens/weekly_planner_screen.dart',
        // Paywall: purchase in flight.
        'lib/screens/paywall_screen.dart',
        // Profile: account-linking in flight.
        'lib/screens/profile_screen.dart',
        // Share card: image render in flight.
        'lib/widgets/post_cook_share_card.dart',
        // Cook Mode: the step progress bar, and the SOS chat typing bubble —
        // a conversation, not a recipe generation, with its own affordance.
        'lib/screens/one_pan_cooking_roadmap_screen.dart',
      };

      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final rel = f.path.replaceAll(r'\', '/');
        if (allowed.contains(rel)) continue;
        final src = f.readAsStringSync();
        if (src.contains('CircularProgressIndicator') ||
            src.contains('LinearProgressIndicator')) {
          offenders.add(rel);
        }
      }
      expect(offenders, isEmpty,
          reason: 'a generation wait must use GenerationLoadingCard');
    });
  });
}
