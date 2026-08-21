import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/onboarding_screen.dart';
import 'package:optimeal/services/user_profile_service.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/widgets/onboarding_visuals.dart';

/// Onboarding redesign (2026-08-22).
///
/// Two of these are correctness tests rather than UI tests, and they are the
/// reason this file exists:
///
/// - **Skip must complete.** It previously set only the local flag and routed
///   to `/paywall`, which the router's own `!isOnboarded` redirect bounced
///   straight back to onboarding — so Skip did not skip.
/// - **No slide may promise something the app no longer does.** Checkboxes and
///   the shopping list were both advertised to every new user long after they
///   were cut.

/// Drives the real router so the `!isOnboarded → /onboarding` redirect is in
/// play — completion has to satisfy that redirect, not merely call `go`.
Widget _app(UserProfileController profile) {
  final router = AppRouter.createRouter(profile);
  return ChangeNotifierProvider.value(
    value: profile,
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<UserProfileController> _freshProfile() async {
  final controller = UserProfileController(UserProfileService());
  await controller.load();
  return controller;
}

Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(600, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('structure', () {
    testWidgets('four slides, dots, CTA progression, Skip hidden on the last',
        (tester) async {
      await _pump(tester, _app(await _freshProfile()));

      // Slide 1.
      expect(find.text('Hi, I\'m Chef Harris.'), findsOneWidget);
      expect(find.byType(SpoonAndBowlIllustration), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      await _next(tester);
      expect(find.byType(FridgeIllustration), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);

      await _next(tester);
      expect(find.byType(MiniCuePanelPreview), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      await _next(tester);
      // Slide 4: the CTA becomes the finish label and Skip disappears.
      expect(find.byType(MiniWeekStripPreview), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
      expect(find.text('Next'), findsNothing);
      expect(find.text('Let\'s cook'), findsOneWidget);
    });

    testWidgets('the dots track the page and there are exactly four',
        (tester) async {
      await _pump(tester, _app(await _freshProfile()));

      List<double> dotWidths() => tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((c) => c.constraints?.maxWidth ?? 0)
          .toList();

      expect(dotWidths(), hasLength(OnboardingScreen.slideCount));
      // The active dot is the wide one.
      expect(dotWidths().first, 18);
      expect(dotWidths().last, 8);

      await _next(tester);
      expect(dotWidths().first, 8);
      expect(dotWidths()[1], 18);
    });

    testWidgets('one terracotta CTA on screen at a time', (tester) async {
      await _pump(tester, _app(await _freshProfile()));
      expect(find.byType(FilledButton), findsOneWidget);
      await _next(tester);
      await _next(tester);
      await _next(tester);
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });

  group('stale promises are gone', () {
    /// Every user-visible string on every slide, harvested by walking the
    /// pages rather than by reading the source — a string that only appears
    /// after a page change still counts as shown to the user.
    Future<List<String>> allSlideText(WidgetTester tester) async {
      final seen = <String>[];
      void harvest() {
        for (final t in tester.widgetList<Text>(find.byType(Text))) {
          final s = t.data;
          if (s != null) seen.add(s.toLowerCase());
        }
      }

      harvest();
      for (var i = 0; i < OnboardingScreen.slideCount - 1; i++) {
        await _next(tester);
        harvest();
      }
      return seen;
    }

    testWidgets('no checkbox, shopping list, or unsourced CHF claim',
        (tester) async {
      await _pump(tester, _app(await _freshProfile()));
      final text = (await allSlideText(tester)).join(' | ');

      // Cut with the pre-cook merge.
      expect(text, isNot(contains('checkbox')));
      expect(text, isNot(contains('tick')));
      // Cut entirely in August.
      expect(text, isNot(contains('shopping list')));
      // Never sourced or signed.
      expect(text, isNot(contains('chf')));
      expect(text, isNot(contains('600')));
      // Defensive persona framing, replaced by leading with what he is.
      expect(text, isNot(contains('not a chatbot')));
      expect(text, isNot(contains('pretending')));
    });

    testWidgets('slide 1 leads with what Chef Harris is', (tester) async {
      await _pump(tester, _app(await _freshProfile()));
      expect(find.textContaining('real cooking teacher'), findsOneWidget);
      // No hardcoded year count.
      expect(find.textContaining('years of experience'), findsNothing);
      expect(find.textContaining('20 years'), findsNothing);
    });

    testWidgets('slide 3 teaches senses, not checkboxes', (tester) async {
      await _pump(tester, _app(await _freshProfile()));
      await _next(tester);
      await _next(tester);
      expect(find.textContaining('senses'), findsOneWidget);
      // The sage cue panel is the visual, pre-teaching green = teaching.
      expect(find.textContaining('HOW YOU KNOW'), findsOneWidget);
    });

    testWidgets('slide 4 previews real day states', (tester) async {
      await _pump(tester, _app(await _freshProfile()));
      await _next(tester);
      await _next(tester);
      await _next(tester);

      // ✓ / today·Cook / dashed + — the three states the planner actually has.
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.text('Cook'), findsOneWidget);
      expect(find.text('Nothing planned'), findsOneWidget);
      expect(find.text('+'), findsOneWidget);
      // Bookmark-everywhere mention.
      expect(find.textContaining('Bookmark'), findsOneWidget);
    });
  });

  group('routing and completion', () {
    testWidgets('Finish completes and lands on Home', (tester) async {
      final profile = await _freshProfile();
      await _pump(tester, _app(profile));

      await _next(tester);
      await _next(tester);
      await _next(tester);
      await tester.tap(find.text('Let\'s cook'));
      await tester.pumpAndSettle();

      expect(AppRouter.lastRouter!.state.uri.path, AppRoutes.home);
      expect(profile.isOnboarded, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(OnboardingScreen.hasSeenOnboardingKey), isTrue);
    });

    testWidgets('Skip ALSO completes and lands on Home', (tester) async {
      // The bug this pins: Skip used to set only the local flag and route to
      // /paywall, which the router bounced straight back to onboarding.
      final profile = await _freshProfile();
      await _pump(tester, _app(profile));

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(AppRouter.lastRouter!.state.uri.path, AppRoutes.home);
      expect(profile.isOnboarded, isTrue,
          reason: 'without this the router redirects straight back');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(OnboardingScreen.hasSeenOnboardingKey), isTrue);
    });

    testWidgets('Skip from a middle slide completes too', (tester) async {
      final profile = await _freshProfile();
      await _pump(tester, _app(profile));
      await _next(tester);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(AppRouter.lastRouter!.state.uri.path, AppRoutes.home);
      expect(profile.isOnboarded, isTrue);
    });

    testWidgets('the completed user is not shown onboarding again',
        (tester) async {
      final profile = await _freshProfile();
      await _pump(tester, _app(profile));
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      // The redirect is the real check: asking for onboarding again bounces.
      AppRouter.lastRouter!.go(AppRoutes.onboarding);
      await tester.pumpAndSettle();
      expect(AppRouter.lastRouter!.state.uri.path, AppRoutes.home);
      expect(find.byType(OnboardingScreen), findsNothing);
    });
  });

  group('the paywall has left the onboarding path', () {
    /// Strips comments, so the class doc that RECORDS the removed route does
    /// not read as the route still being there.
    String codeOnly(String src) => src
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i == -1 ? l : l.substring(0, i);
        })
        .join('\n');

    test('no source file in the onboarding flow references it', () {
      // A source scan, not a widget assertion: the old route was reachable
      // from a handler, and a widget test only proves the paths it walks.
      final onboarding = codeOnly(
          File('lib/screens/onboarding_screen.dart').readAsStringSync());
      expect(onboarding, isNot(contains('paywall')));
      expect(onboarding, isNot(contains('Paywall')));
    });

    test('exactly one route into the paywall remains, app-wide', () {
      // The census. `UpgradePromptSheet` is the only entry point left, and it
      // is a mid-app upsell, not part of onboarding.
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final rel = f.path.replaceAll(r'\', '/');
        if (rel == 'lib/nav.dart' || rel == 'lib/screens/paywall_screen.dart') {
          continue; // the route definition and the screen itself
        }
        final src = f.readAsStringSync();
        if (src.contains('AppRoutes.paywall') || src.contains("'/paywall'")) {
          offenders.add(rel);
        }
      }
      expect(offenders, ['lib/widgets/upgrade_prompt_sheet.dart']);
    });
  });

  group('the dev replay affordance', () {
    // The reset is asserted directly rather than through the Profile screen,
    // which cannot be pumped without a live Supabase instance. That the row
    // calling it is dev-gated is asserted in source, below.
    testWidgets('resets BOTH flags, so the router lets the user back in',
        (tester) async {
      final profile = await _freshProfile();
      await _pump(tester, _app(profile));
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(profile.isOnboarded, isTrue);

      await OnboardingScreen.resetForReplay(profile);
      await tester.pumpAndSettle();

      expect(profile.isOnboarded, isFalse,
          reason: 'the flag the router actually gates on');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(OnboardingScreen.hasSeenOnboardingKey), isNull);

      // And the router puts them back at slide 1 without being asked.
      expect(find.text('Hi, I\'m Chef Harris.'), findsOneWidget);
    });

    test('the Profile row is compiled out of release builds', () {
      // `kIsDevEnvironment` is a compile-time constant, so this `if` is the
      // difference between shipping the affordance and not.
      final source =
          File('lib/screens/profile_screen.dart').readAsStringSync();
      final devIndex = source.indexOf('if (kIsDevEnvironment) ...[');
      final rowIndex = source.indexOf('_ReplayOnboardingRow(onReplay:');
      expect(devIndex, greaterThan(-1));
      expect(rowIndex, greaterThan(devIndex),
          reason: 'the row must sit inside the dev guard');
    });
  });
}
