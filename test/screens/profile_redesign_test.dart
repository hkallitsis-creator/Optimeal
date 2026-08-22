import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/config/app_environment.dart';
import 'package:optimeal/screens/profile_screen.dart';
import 'package:optimeal/theme/app_design_tokens.dart';

/// The Profile redesign.
///
/// `ProfileScreen` needs a live Supabase client (it reads
/// `Supabase.instance.client.auth.currentUser` in `build`), so pumping the
/// whole screen here would need a real instance. These assert what can be
/// asserted without one — the composition rules, by source — plus the widgets
/// that stand alone.
void main() {
  final source = File('lib/screens/profile_screen.dart').readAsStringSync();

  // Comments stripped: a comment explaining what was cut is the opposite of
  // the failure being guarded against.
  final code = File('lib/screens/profile_screen.dart')
      .readAsLinesSync()
      .map((l) {
        final t = l.trimLeft();
        if (t.startsWith('//')) return '';
        final i = l.indexOf('//');
        return i == -1 ? l : l.substring(0, i);
      })
      .join(' ');

  group('the cuts', () {
    test('the Language card is gone, offered languages and all', () {
      // Deutsch/Français/Italiano were offered and none of them ships — the
      // same stale-promise class the onboarding rewrite cut.
      for (final needle in ['Deutsch', 'Français', 'Italiano']) {
        expect(code.contains(needle), isFalse, reason: needle);
      }
      expect(code.contains('_languageOptions'), isFalse);
    });

    test('the language FIELD survives on the model — no migration', () {
      // B2: the preference stays in the model and the store, it just has no
      // UI. Dropping it would have been a migration for nothing.
      final profileModel =
          File('lib/models/user_profile.dart').readAsStringSync();
      expect(profileModel.contains('language'), isTrue);
      expect(source.contains('_language'), isTrue,
          reason: 'still written on save, still round-trips');
    });

    test('every per-card explainer paragraph is gone', () {
      for (final needle in [
        'What should Chef Harris call you?',
        'Helps Chef Harris tailor',
        'Select any allergens or intolerances',
        'Tune instructions to your style',
        'Choose the app language',
        'Scale ingredients automatically',
      ]) {
        expect(code.contains(needle), isFalse, reason: needle);
      }
    });

    test('the old mixed selection widgets are gone', () {
      for (final cls in [
        'class DietOptionTile',
        'class ConfidenceOptionRow',
        'class ProfileSectionCard',
      ]) {
        expect(code.contains(cls), isFalse, reason: cls);
      }
    });

    test('no Material radio anywhere on the screen', () {
      expect(code.contains('Radio<'), isFalse);
      expect(code.contains('RadioListTile'), isFalse);
    });

    test('the Save Profile button is gone — the screen autosaves', () {
      expect(code.contains('Save Profile'), isFalse);
      expect(source.contains('_scheduleAutoSave'), isTrue);
    });
  });

  group('B1 — kit rules', () {
    test('exactly one terracotta filled CTA on the screen itself', () {
      // Scoped to the screen, deliberately. The _SecureAccountSheet has its
      // own terracotta submit button, but it is a modal on a different
      // surface — it is never on screen at the same time as the card CTA that
      // opens it. "One terracotta CTA" is a per-surface rule.
      final sheetStart = code.indexOf('class _SecureAccountSheet');
      expect(sheetStart, greaterThan(0));
      final screenOnly = code.substring(0, sheetStart);

      final matches = RegExp(r'backgroundColor: AppDesignTokens\.ctaTerracotta')
          .allMatches(screenOnly)
          .length;
      expect(matches, 1,
          reason: 'the one CTA is "Secure my account"; found $matches');
    });

    test('deep forest is never a fill here', () {
      expect(
        code.contains('backgroundColor: AppDesignTokens.deepForest'),
        isFalse,
      );
    });

    test('selection is champagne fill, in one place', () {
      expect(source.contains('class SelectionChip'), isTrue);
      expect(source.contains('AppDesignTokens.champagneTint'), isTrue);
    });
  });

  group('B3 — the Confidence Climb is read-only', () {
    test('there is no un-mark or self-declare path', () {
      expect(code.contains('_unmarkComfortable'), isFalse);
      expect(code.contains('markNotComfortable'), isFalse,
          reason: 'the Climb is earned, not set — in either direction');
    });

    test('the comfortable-techniques rows carry no tap handler', () {
      // Extract the widget and assert it has no interaction at all.
      final start = source.indexOf('class _ComfortableTechniques');
      expect(start, greaterThan(0));
      final end = source.indexOf('class _DevSection');
      final widget = source.substring(start, end);

      for (final interactive in [
        'onTap',
        'GestureDetector',
        'InkWell',
        'TextButton',
        'IconButton',
      ]) {
        expect(widget.contains(interactive), isFalse, reason: interactive);
      }
    });

    test('gold is used only for the earned state', () {
      final start = source.indexOf('class _ComfortableTechniques');
      final end = source.indexOf('class _DevSection');
      final widget = source.substring(start, end);
      expect(widget.contains('goldEarnedOnLight'), isTrue);
    });
  });

  group('B4 — the dev section', () {
    test('it is gated on the environment constant', () {
      expect(code.contains('if (kIsDevEnvironment)'), isTrue);
      expect(code.contains('_DevSection'), isTrue);
    });

    test('the gate is a compile-time constant, so it folds away in prod', () {
      // kIsDevEnvironment is `const bool`, which is what makes the branch —
      // and the whole dev section — disappear from a prod build rather than
      // merely being hidden at runtime. Same mechanism as the DEV badge.
      expect(kIsDevEnvironment, isA<bool>());
      final envSource =
          File('lib/config/app_environment.dart').readAsStringSync();
      expect(envSource.contains('const bool kIsDevEnvironment'), isTrue);
    });

    test('Replay onboarding is wired to the real reset', () {
      expect(source.contains('OnboardingScreen.resetForReplay'), isTrue);
      expect(source.contains('_ReplayOnboardingRow'), isTrue);
    });
  });

  group('B5 — the auth flow is untouched', () {
    test('the secure-account sheet is still opened the same way', () {
      expect(source.contains('_SecureAccountSheet'), isTrue);
      expect(source.contains('AppBottomSheet.show'), isTrue);
    });
  });

  group('the standalone widgets', () {
    testWidgets('a selected chip is a champagne fill, not a border',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (_) => const _ChipHarness(selected: true),
          ),
        ),
      ));
      await tester.pump();

      final fills = tester
          .widgetList<Material>(find.byType(Material))
          .where((m) => m.color == AppDesignTokens.champagneTint);
      expect(fills, isNotEmpty);
    });

    testWidgets('allergen chips wrap and never clip at 360 px',
        (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: _AllergenWrapHarness()),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate((w) =>
            w is SingleChildScrollView &&
            w.scrollDirection == Axis.horizontal),
        findsNothing,
      );
    });
  });
}

/// The chip in isolation — `SelectionChip` is public precisely so it can be
/// asserted without a live Supabase client.
class _ChipHarness extends StatelessWidget {
  const _ChipHarness({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) => Center(
        child: SelectionChip(
          label: 'Vegan',
          selected: selected,
          onTap: () {},
        ),
      );
}

class _AllergenWrapHarness extends StatelessWidget {
  const _AllergenWrapHarness();

  static const options = <String>[
    'Gluten',
    'Lactose/Dairy',
    'Tree Nuts',
    'Peanuts',
    'Fish',
    'Crustaceans',
    'Molluscs',
    'Soy',
    'Sesame',
    'Celery',
    'Mustard',
    'Sulfites/Alcohol',
    'Lupin',
    'Egg',
  ];

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in options)
                SelectionChip(label: o, selected: false, onTap: () {}),
            ],
          ),
        ),
      );
}
