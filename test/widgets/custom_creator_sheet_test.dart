import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/services/user_profile_service.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/custom_ai_recipe_creator_sheet.dart';

/// The Custom Recipe Creator sheet.
///
/// What it replaced: an explainer paragraph the field's placeholder already
/// said, bolt-icon chips, a sparkle chip beside the title, a four-line
/// textarea that invited an essay, and "✨ Generate Recipe" — emoji in a CTA.

Widget _host(Widget child) {
  final profile = UserProfileController(UserProfileService());
  return MultiProvider(
    providers: [ChangeNotifierProvider.value(value: profile)],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final source =
      File('lib/widgets/custom_ai_recipe_creator_sheet.dart').readAsStringSync();

  group('the cuts', () {
    testWidgets('no explainer paragraph, no sparkle chip', (tester) async {
      await tester.pumpWidget(_host(const CustomAiRecipeCreatorSheet()));
      await tester.pump();

      expect(find.textContaining("I'll generate"), findsNothing);
      expect(find.byIcon(Icons.auto_awesome_rounded), findsNothing,
          reason: 'the title stands alone');
      expect(find.byIcon(Icons.bolt_rounded), findsNothing,
          reason: 'chips carry no icons');
    });

    testWidgets('the field is one line, not a textarea', (tester) async {
      await tester.pumpWidget(_host(const CustomAiRecipeCreatorSheet()));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.maxLines, 1, reason: 'a craving is a phrase');
    });

    testWidgets('no servings control on the sheet', (tester) async {
      // Signed: the sheet stays one thought long. The profile default flows
      // in silently; the adjuster is on the recipe overview.
      await tester.pumpWidget(_host(const CustomAiRecipeCreatorSheet()));
      await tester.pump();

      expect(find.textContaining('Serves'), findsNothing);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.byIcon(Icons.remove_rounded), findsNothing);
    });
  });

  group('quick-fill chips fill, they do not filter or submit', () {
    testWidgets('tapping writes editable text into the field', (tester) async {
      await tester.pumpWidget(_host(const CustomAiRecipeCreatorSheet()));
      await tester.pump();

      await tester.tap(find.text('Quick Pasta'));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Quick pasta with what I have');
      expect(find.byType(TextField), findsOneWidget,
          reason: 'still the form — a chip is not a submit');
    });

    testWidgets('the filled-from chip shows champagne', (tester) async {
      await tester.pumpWidget(_host(const CustomAiRecipeCreatorSheet()));
      await tester.pump();

      await tester.tap(find.text('Cozy Comfort'));
      await tester.pump();

      final champagne = tester
          .widgetList<Material>(find.byType(Material))
          .where((m) => m.color == AppDesignTokens.champagneTint);
      expect(champagne, hasLength(1),
          reason: 'exactly the tapped chip is highlighted');
    });

    testWidgets('editing the text clears the highlight', (tester) async {
      await tester.pumpWidget(_host(const CustomAiRecipeCreatorSheet()));
      await tester.pump();

      await tester.tap(find.text('High Protein'));
      await tester.pump();
      expect(
        tester
            .widgetList<Material>(find.byType(Material))
            .where((m) => m.color == AppDesignTokens.champagneTint),
        hasLength(1),
      );

      await tester.enterText(find.byType(TextField), 'High protein but vegan');
      await tester.pump();

      expect(
        tester
            .widgetList<Material>(find.byType(Material))
            .where((m) => m.color == AppDesignTokens.champagneTint),
        isEmpty,
        reason: 'the chip stops claiming text it no longer owns',
      );
    });
  });

  group('generate swaps in place', () {
    test('the wait replaces the sheet content, it does not navigate', () {
      // No route push anywhere in the generating branch — the wait is a swap.
      final start = source.indexOf('if (_isGenerating) {');
      expect(start, greaterThan(0));
      final branch = source.substring(start, start + 600);

      expect(branch.contains('GenerationLoadingCard'), isTrue);
      expect(branch.contains('context.push'), isFalse);
      expect(branch.contains('showModalBottomSheet'), isFalse,
          reason: 'sheets never stack');
      expect(branch.contains('height: 420'), isTrue,
          reason: 'the 420px sheet-height case on the device checklist');
    });

    test('the typed craving is the subject line', () {
      expect(source.contains('subject: _controller.text.trim().isEmpty'), isTrue,
          reason: 'the user sees their own words while they wait');
    });
  });

  group('the CTA', () {
    testWidgets('is terracotta, singular, and carries no emoji',
        (tester) async {
      await tester.pumpWidget(_host(const CustomAiRecipeCreatorSheet()));
      await tester.pump();

      final filled = tester
          .widgetList<FilledButton>(find.byType(FilledButton))
          .where((b) =>
              b.style?.backgroundColor?.resolve({}) ==
              AppDesignTokens.ctaTerracotta);
      expect(filled, hasLength(1));

      expect(find.text('Generate recipe'), findsOneWidget);
      expect(find.textContaining('✨'), findsNothing);
    });

    testWidgets('an empty field is refused without generating',
        (tester) async {
      await tester.pumpWidget(_host(const CustomAiRecipeCreatorSheet()));
      await tester.pump();

      await tester.tap(find.text('Generate recipe'));
      await tester.pump();

      expect(find.textContaining('Type a dish'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget,
          reason: 'still the form, no wait card');
    });
  });

  group('both entry points are the same widget', () {
    test('Home and the planner both open CustomAiRecipeCreatorSheet', () {
      final home = File('lib/screens/home_dashboard_screen.dart').readAsStringSync();
      final planner =
          File('lib/screens/weekly_planner_screen.dart').readAsStringSync();

      expect(home.contains('CustomAiRecipeCreatorSheet'), isTrue);
      expect(planner.contains('CustomAiRecipeCreatorSheet'), isTrue);
    });
  });

  group('failure state', () {
    test('is a quiet card, and the retry is the same single CTA', () {
      expect(source.contains('class _CreatorErrorCard'), isTrue);
      expect(source.contains("_error == null ? 'Generate recipe' : 'Try again'"),
          isTrue,
          reason: 'retry relabels the one CTA rather than adding a second');
      // Quiet, not an error-red alarm.
      expect(source.contains('errorContainer'), isFalse);
    });

    test('typed text is never cleared on failure', () {
      final start = source.indexOf('} catch');
      final tail = source.substring(start, start + 400);
      expect(tail.contains('_controller.clear'), isFalse);
      expect(tail.contains("_controller.text = ''"), isFalse);
    });
  });
}
