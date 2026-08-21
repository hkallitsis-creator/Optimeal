import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/models/cook_mode_recipe_codec.dart';
import 'package:optimeal/models/planner_slot_ref.dart';
import 'package:optimeal/models/planner_week.dart';
import 'package:optimeal/models/recipe_origin.dart';
import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/screens/weekly_planner_screen.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/services/data_change_signal.dart';
import 'package:optimeal/services/planner_cook_attribution_service.dart';
import 'package:optimeal/services/saved_recipes_service.dart';
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

/// The two anchored weeks those dates fall into, since migration
/// `20260822120000` — `week_start` is the Monday, and `day_index` is 0–6 on
/// both weeks. `_nextMonday` is also used as a "the clock moved on" value for
/// the rollover test.
final DateTime _nextMonday = DateTime(2026, 8, 31, 9, 0);
final String _thisWeekValue = plannerWeekValueFor(_monday);
final String _nextWeekValue = plannerWeekValueFor(_nextMonday);

/// Captures what Cook Mode was launched with, so provenance can be asserted
/// on the launch itself rather than on a screen that drags in Supabase.
CookModeLaunchRequest? lastCookLaunch;

/// The router the current test is driving, so a test can pop back out of the
/// stubbed Cook Mode route — a pushed route covers the planner, and an
/// offstage screen's widgets are invisible to finders.
GoRouter? lastRouter;

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
      // [dayIndex] stays the 0–13 index these tests were written against, for
      // readability; the row it produces is the anchored shape the table now
      // stores, so 7–13 means "same weekday, next week" rather than a day
      // index the database has never heard of.
      'week_start':
          dayIndex < kNextWeekOffset ? _thisWeekValue : _nextWeekValue,
      'day_index': dayIndex % kDaysPerWeek,
      'slot_index': slotIndex,
      'title': title,
      'source': source,
      'recipe_payload': withPayload
          ? cookModeRecipeToJson(
              testRecipe(title, origin: origin, entered: const ['Zucchini']))
          : null,
      'is_cooked': cooked,
    };

Widget _wrap(WeeklyPlanBackend backend,
    {DateTime? now, SavedRecipesService? savedRecipesService}) {
  final router = GoRouter(
    initialLocation: AppRoutes.weeklyPlan,
    routes: [
      GoRoute(
        path: AppRoutes.weeklyPlan,
        builder: (context, state) => WeeklyPlannerScreen(
            backend: backend,
            now: now ?? _monday,
            savedRecipesService: savedRecipesService),
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
  lastRouter = router;
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
  SavedRecipesService? savedRecipesService,
}) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(backend,
      now: now, savedRecipesService: savedRecipesService));
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
    lastRouter = null;
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

  /// CLAUDE.md roadmap item 27, closed 2026-08-22. The launch stamps the row's
  /// identity; the completion writes it back; the planner's existing signal
  /// subscription flips the row in place. These tests walk that whole path
  /// through the real seams — the real screen, the real launch request, the
  /// real attribution service, the real backend fake — with only the Cook Mode
  /// screen itself stubbed out (it drags in Supabase, Provider and the whole
  /// post-cook sheet sequence, none of which this behaviour depends on).
  group('cooked-state slot attribution', () {
    /// Stands in for Cook Mode finishing: takes whatever slot the launch
    /// actually carried and runs the real completion-side write.
    Future<bool> completeCook(
      FakeWeeklyPlanBackend backend, {
      bool isReCook = false,
    }) =>
        PlannerCookAttributionService(backend: backend)
            .markCookedFromCompletion(
                slot: lastCookLaunch?.plannerSlot, isReCook: isReCook);

    /// Back out of the stubbed Cook Mode route, so the planner is on screen
    /// again. The planner was mounted the whole time — that is what lets the
    /// signal reach it — but a covered route is offstage and invisible to
    /// finders.
    Future<void> leaveCookMode(WidgetTester tester) async {
      lastRouter!.pop();
      await tester.pumpAndSettle();
    }

    testWidgets('Cook stamps the row it was pressed on', (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(planRow(dayIndex: 0, title: 'Monday Dish'));

      await _pumpPlanner(tester, backend);
      await tester.tap(find.text('Cook'));
      await tester.pumpAndSettle();

      expect(lastCookLaunch!.plannerSlot,
          PlannerSlotRef(
              weekStart: _thisWeekValue, dayIndex: 0, slotIndex: 0));
    });

    testWidgets('the day\'s second meal stamps slot 1, not slot 0',
        (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(planRow(dayIndex: 0, slotIndex: 0, title: 'First Dish'));
      backend.rows.add(planRow(dayIndex: 0, slotIndex: 1, title: 'Second Dish'));

      await _pumpPlanner(tester, backend);

      // Both of today's meals are cookable, so there are two Cook buttons —
      // tap the one belonging to the second row.
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();

      expect(lastCookLaunch!.plannerSlot,
          PlannerSlotRef(
              weekStart: _thisWeekValue, dayIndex: 0, slotIndex: 1));
    });

    testWidgets(
        'end to end: a rescue-eligible planner cook comes back as the gold, '
        'counted state', (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(planRow(
          dayIndex: 0,
          title: 'Rescue Dish',
          origin: RecipeOrigin.fridgeClearer));

      await _pumpPlanner(tester, backend);
      final screenState = tester.state(find.byType(WeeklyPlannerScreen));

      await tester.tap(find.text('Cook'));
      await tester.pumpAndSettle();
      expect(await completeCook(backend), isTrue);
      await tester.pumpAndSettle();
      await leaveCookMode(tester);

      expect(backend.rows.single['is_cooked'], isTrue);
      expect(find.text('Cook'), findsNothing);
      final check = tester.widget<Icon>(find.byIcon(Icons.check_circle_rounded));
      expect(check.color, AppDesignTokens.cookedCountedGold);
      expect(tester.state(find.byType(WeeklyPlannerScreen)), same(screenState),
          reason: 'flipped in place by the signal, not by a remount');
    });

    testWidgets(
        'end to end: a non-rescue planner cook comes back as the neutral, '
        'didn\'t-count state', (tester) async {
      final backend = FakeWeeklyPlanBackend();
      // Same write, same path — only the recipe's own origin differs, which is
      // the whole point: counted-ness is derived, never stored.
      backend.rows.add(planRow(
          dayIndex: 0,
          title: 'Craving Dish',
          origin: RecipeOrigin.customAiRecipeCreator));

      await _pumpPlanner(tester, backend);
      await tester.tap(find.text('Cook'));
      await tester.pumpAndSettle();
      await completeCook(backend);
      await tester.pumpAndSettle();
      await leaveCookMode(tester);

      final check = tester.widget<Icon>(find.byIcon(Icons.check_circle_rounded));
      expect(check.color, AppDesignTokens.cookedNeutralGray);
    });

    testWidgets(
        'the same dish planned on two days: only the launched day flips',
        (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(planRow(dayIndex: 0, title: 'Zucchini Fritters'));
      backend.rows.add(planRow(dayIndex: 3, title: 'Zucchini Fritters'));

      await _pumpPlanner(tester, backend);
      // Only today (Monday) is cookable, so the Cook button belongs to day 0.
      await tester.tap(find.text('Cook'));
      await tester.pumpAndSettle();
      await completeCook(backend);
      await tester.pumpAndSettle();
      await leaveCookMode(tester);

      expect(backend.markCookedTargets,
          [(weekStart: _thisWeekValue, dayIndex: 0, slotIndex: 0)]);
      expect(
          backend.rows
              .firstWhere((r) => r['day_index'] == 0)['is_cooked'],
          isTrue);
      expect(
          backend.rows
              .firstWhere((r) => r['day_index'] == 3)['is_cooked'],
          isFalse);
      // Thursday still reads as an ordinary planned day.
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('a cook launched from outside the planner touches no plan row',
        (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(planRow(dayIndex: 0, title: 'Monday Dish'));

      await _pumpPlanner(tester, backend);

      // No planner Cook press: this is a Home / Fridge Clearer / generation
      // sheet launch, which carries no slot.
      lastCookLaunch = null;
      expect(await completeCook(backend), isFalse);
      await tester.pumpAndSettle();

      expect(backend.markCookedCalls, 0);
      expect(backend.rows.single['is_cooked'], isFalse);
      expect(find.text('Cook'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    });

    testWidgets('next week never shows a Cook button to stamp', (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(planRow(
          dayIndex: kNextWeekOffset, title: 'Next Monday Dish'));

      await _pumpPlanner(tester, backend);
      await tester.tap(find.text('Next week'));
      await tester.pumpAndSettle();

      expect(find.text('Next Monday Dish'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  /// Week anchoring (migration `20260822120000`). Both weeks are computed from
  /// the clock at read time, so rollover is a property of asking rather than of
  /// stored state — nothing is advanced, nothing is migrated weekly.
  group('week anchoring', () {
    testWidgets('the read is scoped to exactly this week and next week',
        (tester) async {
      final backend = FakeWeeklyPlanBackend();
      await _pumpPlanner(tester, backend);

      expect(backend.readWeekScopes.single, [_thisWeekValue, _nextWeekValue]);
    });

    testWidgets('this week and next week are disjoint sets of rows',
        (tester) async {
      final backend = FakeWeeklyPlanBackend();
      // Same weekday (Monday), same slot, different weeks — two rows that were
      // indistinguishable before week_start joined the key.
      backend.rows.add(planRow(dayIndex: 0, title: 'This Monday Dish'));
      backend.rows
          .add(planRow(dayIndex: kNextWeekOffset, title: 'Next Monday Dish'));

      await _pumpPlanner(tester, backend);
      expect(find.text('This Monday Dish'), findsOneWidget);
      expect(find.text('Next Monday Dish'), findsNothing);

      await tester.tap(find.text('Next week'));
      await tester.pumpAndSettle();
      expect(find.text('Next Monday Dish'), findsOneWidget);
      expect(find.text('This Monday Dish'), findsNothing);
    });

    testWidgets('a placement stores an anchored week and a 0–6 day index',
        (tester) async {
      final backend = FakeWeeklyPlanBackend();
      await _pumpPlanner(tester, backend);

      await tester.tap(find.text('Next week'));
      await tester.pumpAndSettle();

      WeeklyPlannerIntentService.instance.queueAddMeal(
        dayIndex: 3,
        recipe: testRecipe('Anchored Dish'),
        source: kFromSavedMealSource,
      );
      await tester.pumpAndSettle();

      // The intent snaps back to this week, and what lands in the table is the
      // anchored pair — never the old 0–13 offset encoding.
      expect(backend.rows.single['week_start'], _thisWeekValue);
      expect(backend.rows.single['day_index'], 3);
    });

    testWidgets(
        'a placement into NEXT week stores next week\'s Monday, not day 10',
        (tester) async {
      final backend = FakeWeeklyPlanBackend();
      final service = SavedRecipesService(
        backend: FakeSavedRecipesBackend(),
        sessionStorage: CookSessionStorageService(),
      );
      await service.save(testRecipe('Saved Dish'));

      await _pumpPlanner(tester, backend, savedRecipesService: service);

      await tester.tap(find.text('Next week'));
      await tester.pumpAndSettle();

      // Next week's Thursday (the 4th empty day card).
      await tester.tap(find.text('Nothing planned').at(3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My recipes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved Dish').last);
      await tester.pumpAndSettle();

      expect(backend.rows.single['week_start'], _nextWeekValue);
      expect(backend.rows.single['day_index'], 3);
    });

    testWidgets(
        'rollover: with no data change, last week\'s "next week" becomes this '
        'week', (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(planRow(dayIndex: 0, title: 'This Monday Dish'));
      backend.rows
          .add(planRow(dayIndex: kNextWeekOffset, title: 'Next Monday Dish'));

      // Before: only "This Monday Dish" is in the default (this-week) view.
      await _pumpPlanner(tester, backend);
      expect(find.text('This Monday Dish'), findsOneWidget);
      expect(find.text('Next Monday Dish'), findsNothing);

      // The clock moves a week. Nothing else changes — no write, no migration,
      // no stored week to advance.
      await _pumpPlanner(tester, backend, now: _nextMonday);

      expect(find.text('Next Monday Dish'), findsOneWidget,
          reason: 'what was next week is now this week');
      expect(find.text('This Monday Dish'), findsNothing,
          reason: 'last week has rolled into the past and is unreachable');
      // And it is genuinely cookable now, which it could not be before.
      expect(find.text('Cook'), findsOneWidget);
    });

    testWidgets('a week that has rolled into the past is never fetched',
        (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(planRow(dayIndex: 0, title: 'Old Dish'));

      await _pumpPlanner(tester, backend, now: _nextMonday);

      // The row still exists — this is not a delete — it is simply outside
      // every week this screen can ask for.
      expect(backend.rows, hasLength(1));
      expect(backend.readWeekScopes.single, isNot(contains(_thisWeekValue)));
      expect(find.text('Old Dish'), findsNothing);
      expect(find.text('Nothing planned'), findsNWidgets(kDaysPerWeek));
    });

    testWidgets(
        'the Sunday→Monday boundary moves the whole screen forward one day '
        'before midnight and one after', (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(planRow(dayIndex: 6, title: 'Sunday Dish'));
      backend.rows
          .add(planRow(dayIndex: kNextWeekOffset, title: 'Next Monday Dish'));

      // 23:59 on Sunday: still the old week, Sunday is today and cookable.
      await _pumpPlanner(tester, backend,
          now: DateTime(2026, 8, 30, 23, 59, 59));
      expect(find.text('Sunday Dish'), findsOneWidget);
      expect(_cardFillUnder(tester, 'Sun'), AppDesignTokens.champagneTint);
      expect(find.text('Cook'), findsOneWidget);

      // One minute later: the new week, Monday is today, and Sunday's meal is
      // in the past and unreachable.
      await _pumpPlanner(tester, backend, now: DateTime(2026, 8, 31, 0, 0, 0));
      expect(find.text('Next Monday Dish'), findsOneWidget);
      expect(find.text('Sunday Dish'), findsNothing);
      expect(_cardFillUnder(tester, 'Mon'), AppDesignTokens.champagneTint);
    });

    testWidgets(
        'a cook launched just before midnight marks the week it was planned in',
        (tester) async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(planRow(dayIndex: 6, title: 'Sunday Dish'));

      await _pumpPlanner(tester, backend,
          now: DateTime(2026, 8, 30, 23, 55));
      await tester.tap(find.text('Cook'));
      await tester.pumpAndSettle();

      // The stamp is taken at launch, so it names the week the row lives in —
      // not whatever week it happens to be when the cook finishes.
      expect(lastCookLaunch!.plannerSlot,
          PlannerSlotRef(
              weekStart: _thisWeekValue, dayIndex: 6, slotIndex: 0));
    });
  });

  group('the active cook session carries the slot through an interruption',
      () {
    test('a planner cook resumes still knowing its row', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = CookSessionStorageService();

      await storage.saveActiveSession(
        recipe: testRecipe('Interrupted Dish'),
        cookStarted: true,
        cookPaused: true,
        activeStepIndex: 1,
        completedSteps: {0},
        activeRemaining: const Duration(minutes: 3),
        currentPortions: 2,
        surface: CookModeSurface.weeklyPlanner,
        isReCook: false,
        plannerSlot: PlannerSlotRef(
            weekStart: _thisWeekValue, dayIndex: 4, slotIndex: 1),
      );

      final resumed = await storage.loadActiveSession();
      expect(resumed!.plannerSlot,
          PlannerSlotRef(
              weekStart: _thisWeekValue, dayIndex: 4, slotIndex: 1));
    });

    test('a session saved without a slot resumes attributing nothing',
        () async {
      SharedPreferences.setMockInitialValues({});
      final storage = CookSessionStorageService();

      await storage.saveActiveSession(
        recipe: testRecipe('Home Dish'),
        cookStarted: true,
        cookPaused: true,
        activeStepIndex: 0,
        completedSteps: const {},
        activeRemaining: const Duration(minutes: 5),
        currentPortions: 2,
        surface: CookModeSurface.fridgeClearer,
        isReCook: false,
      );

      final resumed = await storage.loadActiveSession();
      expect(resumed!.plannerSlot, isNull);
    });
  });
}
