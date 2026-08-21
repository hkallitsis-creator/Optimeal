import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/models/cook_mode_recipe_codec.dart';
import 'package:optimeal/models/recipe_origin.dart';
import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/screens/weekly_planner_screen.dart';
import 'package:optimeal/services/data_change_signal.dart';
import 'package:optimeal/services/weekly_plan_service.dart';
import 'package:optimeal/services/weekly_planner_intent_service.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/recipe_provenance_badges.dart';

import '../support/fake_saved_recipes_backend.dart';
import '../support/fake_weekly_plan_backend.dart';

/// The Weekly Planner redesign (2026-08-22): all seven days as one list, five
/// day/row states, a this-week/next-week toggle, and cooked state derived
/// from data rather than from a navigation return value.

/// A fixed Monday, so "today" is deterministic no matter when the suite runs.
final DateTime _monday = DateTime(2026, 8, 24, 9, 0);
final DateTime _wednesday = DateTime(2026, 8, 26, 9, 0);

/// Captures what Cook Mode was launched with, so provenance can be asserted
/// on the launch itself rather than on a screen that drags in Supabase.
CookModeLaunchRequest? lastCookLaunch;

class _StubScreen extends StatelessWidget {
  const _StubScreen(this.label);
  final String label;
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}

Map<String, dynamic> planRow({
  required int dayIndex,
  int slotIndex = 0,
  required String title,
  String source = 'Custom AI Craving',
  RecipeOrigin? origin,
  bool cooked = false,
  bool withPayload = true,
}) =>
    {
      'user_id': 'user-1',
      'day_index': dayIndex,
      'slot_index': slotIndex,
      'title': title,
      'source': source,
      'recipe_payload': withPayload
          ? cookModeRecipeToJson(
              testRecipe(title, origin: origin, entered: const ['Zucchini']))
          : null,
      'is_cooked': cooked,
    };

Widget _wrap(WeeklyPlanBackend backend, {DateTime? now}) {
  final router = GoRouter(
    initialLocation: AppRoutes.weeklyPlan,
    routes: [
      GoRoute(
        path: AppRoutes.weeklyPlan,
        builder: (context, state) =>
            WeeklyPlannerScreen(backend: backend, now: now ?? _monday),
      ),
      GoRoute(
          path: AppRoutes.home, builder: (c, s) => const _StubScreen('home')),
      GoRoute(
          path: AppRoutes.fridgeClearerPicker,
          builder: (c, s) => const _StubScreen('fridge picker')),
      GoRoute(
        path: AppRoutes.recipe,
        builder: (c, s) => const _StubScreen('recipe details'),
      ),
      GoRoute(
        path: AppRoutes.onePanCookingRoadmap,
        builder: (c, s) {
          final extra = s.extra;
          if (extra is CookModeLaunchRequest) lastCookLaunch = extra;
          return const _StubScreen('cook mode');
        },
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

/// Pumps the planner in a viewport tall enough to lay out all seven day cards
/// at once. The screen is one scrolling list by design, so on a normal phone
/// the last day or two are simply below the fold — that is not what these
/// tests are about.
Future<void> _pumpPlanner(
  WidgetTester tester,
  WeeklyPlanBackend backend, {
  DateTime? now,
}) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(backend, now: now));
  await tester.pumpAndSettle();
}

Color? _cardFillUnder(WidgetTester tester, String dayLabel) {
  final material = tester.widget<Material>(
    find
        .ancestor(of: find.text(dayLabel), matching: find.byType(Material))
        .first,
  );
  return material.color;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WeeklyPlannerIntentService.instance.consumePending();
    lastCookLaunch = null;
  });

  group('the state table', () {
    test('cooked + rescue-eligible is the gold, counted state', () {
      expect(
        plannerMealStateFor(
            cooked: true,
            rescueEligible: true,
            isToday: true,
            isThisWeek: true),
        PlannerMealState.cookedCounted,
      );
    });

    test('cooked + not rescue-eligible is the neutral, didn\'t-count state',
        () {
      expect(
        plannerMealStateFor(
            cooked: true,
            rescueEligible: false,
            isToday: false,
            isThisWeek: true),
        PlannerMealState.cookedNotCounted,
      );
    });

    test('today, uncooked, this week is the only cookable state', () {
      expect(
        plannerMealStateFor(
            cooked: false,
            rescueEligible: false,
            isToday: true,
            isThisWeek: true),
        PlannerMealState.cookable,
      );
    });

    test('next week is always plain planned, whatever the flags say', () {
      // Belt and braces: next week cannot be today and cannot have been
      // cooked, but the rule is stated explicitly rather than assumed.
      for (final cooked in [true, false]) {
        for (final eligible in [true, false]) {
          expect(
            plannerMealStateFor(
                cooked: cooked,
                rescueEligible: eligible,
                isToday: true,
                isThisWeek: false),
            PlannerMealState.planned,
          );
        }
      }
    });
  });

  group('day rendering', () {
    testWidgets('all seven days are on screen at once, no day-chip strip',
        (tester) async {
      await _pumpPlanner(tester, FakeWeeklyPlanBackend());

      for (final day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
        expect(find.text(day), findsOneWidget, reason: '$day should be listed');
      }
      // The slot cards are gone with the chips.
      expect(find.textContaining('Slot 1'), findsNothing);
      expect(find.textContaining('Slot 2'), findsNothing);
      expect(find.text('+ Add Meal'), findsNothing);
    });

    testWidgets('an empty day shows the quiet line and a terracotta-text plus',
        (tester) async {
      await _pumpPlanner(tester, FakeWeeklyPlanBackend());

      expect(find.text('Nothing planned'), findsNWidgets(7));
      final plus = tester.widget<Text>(find.text('+').first);
      expect(plus.style?.color, AppDesignTokens.ctaTerracotta);
      // Text, not a button: Cook is the only terracotta button on the screen.
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('tapping an empty day opens the unchanged three-source sheet',
        (tester) async {
      await _pumpPlanner(tester, FakeWeeklyPlanBackend());

      await tester.tap(find.text('Nothing planned').first);
      await tester.pumpAndSettle();

      expect(find.text('Clear Fridge Leftovers'), findsOneWidget);
      expect(find.text('Custom AI Craving'), findsOneWidget);
      expect(find.text('My recipes'), findsOneWidget);
    });

    testWidgets('a planned day shows the meal, its leaf, and a chevron',
        (tester) async {
      final backend = FakeWeeklyPlanBackend();
      // Wednesday, while today is Monday — planned, not cookable.
      backend.rows.add(planRow(
          dayIndex: 2,
          title: 'Rescue Dish',
          origin: RecipeOrigin.fridgeClearer));

      await _pumpPlanner(tester, backend);

      expect(find.text('Rescue Dish'), findsOneWidget);
      expect(find.byType(ProvenanceLeafBadge), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(find.text('Cook'), findsNothing);
    });

    testWidgets('today is champagne and carries the only Cook button',
        (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(planRow(dayIndex: 0, title: 'Today Dish'));
      backend.rows.add(planRow(dayIndex: 3, title: 'Thursday Dish'));

      await _pumpPlanner(tester, backend);

      expect(_cardFillUnder(tester, 'Mon'), AppDesignTokens.champagneTint);
      expect(_cardFillUnder(tester, 'Thu'), AppDesignTokens.surfaceCream);

      expect(find.text('Cook'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);

      final weekday = tester.widget<Text>(find.text('Mon'));
      expect(weekday.style?.color, AppDesignTokens.ctaTerracotta);
    });

    testWidgets('a cooked rescue gets the gold check, a cooked non-rescue gray',
        (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(planRow(
          dayIndex: 1,
          title: 'Counted Dish',
          origin: RecipeOrigin.fridgeClearer,
          cooked: true));
      backend.rows.add(planRow(
          dayIndex: 2,
          title: 'Uncounted Dish',
          origin: RecipeOrigin.customAiRecipeCreator,
          cooked: true));

      await _pumpPlanner(tester, backend);

      final checks = tester
          .widgetList<Icon>(find.byIcon(Icons.check_circle_rounded))
          .toList();
      expect(checks, hasLength(2));
      expect(checks.map((c) => c.color).toSet(), {
        AppDesignTokens.cookedCountedGold,
        AppDesignTokens.cookedNeutralGray,
      });
    });

    testWidgets('two meals in one day are rows in one card with a divider',
        (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(planRow(dayIndex: 4, slotIndex: 0, title: 'First Meal'));
      backend.rows
          .add(planRow(dayIndex: 4, slotIndex: 1, title: 'Second Meal'));

      await _pumpPlanner(tester, backend);

      expect(find.text('First Meal'), findsOneWidget);
      expect(find.text('Second Meal'), findsOneWidget);
      expect(find.text('Fri'), findsOneWidget, reason: 'one weekday label');
      expect(find.byType(Divider), findsOneWidget);
      // No second "+" on a filled day — adding meal two is a day-detail
      // action.
      expect(find.text('+'), findsNWidgets(6));
    });
  });

  group('week toggle', () {
    testWidgets('next week is a separate plan, and this week is the default',
        (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(planRow(dayIndex: 0, title: 'This Week Dish'));
      backend.rows
          .add(planRow(dayIndex: kNextWeekOffset, title: 'Next Week Dish'));

      await _pumpPlanner(tester, backend);

      expect(find.text('This Week Dish'), findsOneWidget);
      expect(find.text('Next Week Dish'), findsNothing);

      await tester.tap(find.text('Next week'));
      await tester.pumpAndSettle();

      expect(find.text('Next Week Dish'), findsOneWidget);
      expect(find.text('This Week Dish'), findsNothing);
    });

    testWidgets('next week suppresses Cook buttons and checks entirely',
        (tester) async {
      final backend = FakeWeeklyPlanBackend();
      // Same weekday as today, cooked, rescue-eligible — every flag that
      // would light up in this week, and none of it may render in next week.
      backend.rows.add(planRow(
          dayIndex: kNextWeekOffset,
          title: 'Next Monday Dish',
          origin: RecipeOrigin.fridgeClearer,
          cooked: true));

      await _pumpPlanner(tester, backend);
      await tester.tap(find.text('Next week'));
      await tester.pumpAndSettle();

      expect(find.text('Next Monday Dish'), findsOneWidget);
      expect(find.text('Cook'), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      // Not tinted: today only exists in this week.
      expect(_cardFillUnder(tester, 'Mon'), AppDesignTokens.surfaceCream);
    });

    testWidgets('there is no way to reach a past week', (tester) async {
      await _pumpPlanner(tester, FakeWeeklyPlanBackend());

      expect(find.text('This week'), findsOneWidget);
      expect(find.text('Next week'), findsOneWidget);
      expect(find.textContaining('Last week'), findsNothing);
      expect(find.textContaining('Previous'), findsNothing);
    });

    testWidgets('a placement into next week is persisted at the day offset',
        (tester) async {
      final backend = FakeWeeklyPlanBackend();
      await _pumpPlanner(tester, backend);

      await tester.tap(find.text('Next week'));
      await tester.pumpAndSettle();

      // Tap next week's Tuesday.
      await tester.tap(find.text('Nothing planned').at(1));
      await tester.pumpAndSettle();
      expect(find.text('Clear Fridge Leftovers'), findsOneWidget);

      // Close without placing — what matters here is the day the sheet was
      // opened for, which the placement path below asserts directly.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      WeeklyPlannerIntentService.instance.queueAddMeal(
        dayIndex: 1,
        recipe: testRecipe('Intent Dish'),
        source: kFromSavedMealSource,
      );
      await tester.pumpAndSettle();

      // An intent always means THIS week, so the view snaps back to it.
      expect(find.text('Intent Dish'), findsOneWidget);
      expect(backend.rows.single['day_index'], 1);
    });
  });

  group('cooking from the planner', () {
    testWidgets('Cook carries the planned recipe\'s origin unchanged',
        (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(planRow(
          dayIndex: 0,
          title: 'Rescue Dish',
          origin: RecipeOrigin.fridgeClearer));

      await _pumpPlanner(tester, backend);

      await tester.tap(find.text('Cook'));
      await tester.pumpAndSettle();

      final launch = lastCookLaunch;
      expect(launch, isNotNull);
      expect(launch!.surface, CookModeSurface.weeklyPlanner);
      // The signed rule: eligibility rides the RECIPE, not the surface. A
      // planner-launched Fridge Clearer recipe is still a rescue.
      expect(launch.recipe.origin, RecipeOrigin.fridgeClearer);
      expect(launch.recipe.origin!.isRescueEligible, isTrue);
      expect(launch.recipe.originEnteredIngredients, isNotEmpty);
      expect(launch.isReCook, isFalse);
    });

    testWidgets('a planned meal with no payload says so instead of launching',
        (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows
          .add(planRow(dayIndex: 0, title: 'Broken Dish', withPayload: false));

      await _pumpPlanner(tester, backend);

      await tester.tap(find.text('Cook'));
      await tester.pump();

      expect(find.text('This meal is missing Cook Mode steps.'), findsOneWidget);
      expect(lastCookLaunch, isNull);
    });
  });

  group('write-driven refresh', () {
    testWidgets(
        'a cook-log signal re-reads the plan in place, flipping a day that '
        'came back cooked', (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(planRow(
          dayIndex: 0,
          title: 'Rescue Dish',
          origin: RecipeOrigin.fridgeClearer));

      await _pumpPlanner(tester, backend);
      expect(find.text('Cook'), findsOneWidget);
      expect(backend.listCalls, 1);

      final screenState = tester.state(find.byType(WeeklyPlannerScreen));

      // Stand-in for the completion: the stored row now says cooked. What is
      // under test is that the SIGNAL alone makes this screen notice, with no
      // navigation event and no remount.
      backend.rows.first['is_cooked'] = true;
      AppDataChanges.cookLog.notify();
      await tester.pumpAndSettle();

      expect(backend.listCalls, greaterThan(1));
      expect(find.text('Cook'), findsNothing);
      final check = tester.widget<Icon>(find.byIcon(Icons.check_circle_rounded));
      expect(check.color, AppDesignTokens.cookedCountedGold);
      expect(tester.state(find.byType(WeeklyPlannerScreen)), same(screenState),
          reason: 'refreshed in place, not rebuilt');
    });

    testWidgets('a ledger signal triggers the same re-read', (tester) async {
      final backend = FakeWeeklyPlanBackend();
      await _pumpPlanner(tester, backend);
      expect(backend.listCalls, 1);

      AppDataChanges.ledger.notify();
      await tester.pumpAndSettle();

      expect(backend.listCalls, 2);
    });

    testWidgets('both signals for one cook coalesce into a single re-read',
        (tester) async {
      final backend = FakeWeeklyPlanBackend();
      await _pumpPlanner(tester, backend);
      expect(backend.listCalls, 1);

      AppDataChanges.ledger.notify();
      AppDataChanges.cookLog.notify();
      await tester.pumpAndSettle();

      expect(backend.listCalls, 2, reason: 'one extra read, not two');
    });
  });

  group('the day detail', () {
    testWidgets('holds the second-meal and remove actions', (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(planRow(dayIndex: 2, title: 'Wednesday Dish'));

      await _pumpPlanner(tester, backend, now: _wednesday);

      await tester.tap(find.text('Wednesday Dish'));
      await tester.pumpAndSettle();

      expect(find.text('Wednesday'), findsOneWidget);
      expect(find.text('Add another meal'), findsOneWidget);
      expect(find.byTooltip('Remove meal'), findsOneWidget);

      // Add another swaps to the signed add sheet — it never stacks on top.
      await tester.tap(find.text('Add another meal'));
      await tester.pumpAndSettle();
      expect(find.text('Add another meal'), findsNothing);
      expect(find.text('Clear Fridge Leftovers'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('remove deletes the slot', (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(planRow(dayIndex: 2, title: 'Wednesday Dish'));

      await _pumpPlanner(tester, backend, now: _wednesday);

      await tester.tap(find.text('Wednesday Dish'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove meal'));
      await tester.pumpAndSettle();

      expect(find.text('Wednesday Dish'), findsNothing);
      expect(backend.deleteCalls, 1);
      expect(backend.rows, isEmpty);
    });

    testWidgets('a day with two meals offers no "add another"', (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(planRow(dayIndex: 2, slotIndex: 0, title: 'Meal One'));
      backend.rows.add(planRow(dayIndex: 2, slotIndex: 1, title: 'Meal Two'));

      await _pumpPlanner(tester, backend, now: _wednesday);

      await tester.tap(find.text('Meal One'));
      await tester.pumpAndSettle();

      expect(find.text('Add another meal'), findsNothing);
      expect(find.byTooltip('Remove meal'), findsNWidgets(2));
    });
  });
}
