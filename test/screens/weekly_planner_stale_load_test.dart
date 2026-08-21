import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/models/planner_week.dart';
import 'package:optimeal/models/recipe_origin.dart';
import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/weekly_planner_screen.dart';
import 'package:optimeal/services/weekly_plan_service.dart';
import 'package:optimeal/services/weekly_planner_intent_service.dart';

import '../support/fake_saved_recipes_backend.dart';
import '../support/fake_weekly_plan_backend.dart';

/// Symptom B, device report 2026-08-22: "the Weekly Planner does not show a
/// newly placed recipe until restart."
///
/// The placement itself always worked — the row reached `user_meal_plans`
/// every time. What went wrong is ordering: the planner's one-shot load is
/// issued in `initState`, the queued placement intent is consumed on the first
/// frame, and the load then came back with a snapshot taken *before* that
/// placement's upsert and overwrote it. Restarting the app re-read the table
/// and the meal was there all along.
class _StubScreen extends StatelessWidget {
  const _StubScreen(this.label);
  final String label;
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}

Widget _wrap(WeeklyPlanBackend backend) {
  final router = GoRouter(
    initialLocation: AppRoutes.weeklyPlan,
    routes: [
      GoRoute(
        path: AppRoutes.weeklyPlan,
        builder: (context, state) => WeeklyPlannerScreen(backend: backend),
      ),
      GoRoute(
          path: AppRoutes.home, builder: (c, s) => const _StubScreen('home')),
      GoRoute(
          path: AppRoutes.fridgeClearerPicker,
          builder: (c, s) => const _StubScreen('fridge picker')),
      GoRoute(
          path: AppRoutes.onePanCookingRoadmap,
          builder: (c, s) => const _StubScreen('cook mode')),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The intent is a process-global one-shot; a leftover from a previous
    // test would place a phantom meal in the next one.
    WeeklyPlannerIntentService.instance.consumePending();
  });

  testWidgets(
      'a meal placed from a queued intent survives the initial load landing '
      'after it', (tester) async {
    final backend = FakeWeeklyPlanBackend(holdReads: true);

    // Queued by Fridge Clearer / My recipes / a generation sheet BEFORE the
    // planner is opened — the exact shape of the device report.
    WeeklyPlannerIntentService.instance.queueAddMeal(
      dayIndex: 0,
      recipe: testRecipe('Rescue Dish', origin: RecipeOrigin.fridgeClearer),
      source: kFromSavedMealSource,
    );

    await tester.pumpWidget(_wrap(backend));
    // First frame: the post-frame intent consumer runs and places the meal
    // optimistically. The load is still in flight, holding a snapshot that
    // predates it.
    await tester.pump();
    expect(find.text('Rescue Dish'), findsOneWidget);
    expect(backend.pendingReadCount, 1);

    // The stale snapshot lands.
    backend.completeRead();
    await tester.pump();

    expect(find.text('Rescue Dish'), findsOneWidget,
        reason: 'a load that a local write raced past must not be applied');

    // The placement really was persisted, and the planner re-read once the
    // write settled rather than sitting on state it knows is incomplete.
    expect(backend.upsertCalls, 1);
    expect(backend.rows, hasLength(1));
    expect(backend.listCalls, 2, reason: 'the discarded read is re-issued');

    backend.completeRead();
    await tester.pumpAndSettle();
    expect(find.text('Rescue Dish'), findsOneWidget);
  });

  testWidgets('a load with no competing write still replaces local state',
      (tester) async {
    // The guard must not turn into "never trust the server": with nothing
    // written locally, the snapshot is authoritative.
    final backend = FakeWeeklyPlanBackend();
    backend.rows.add({
      'user_id': 'user-1',
      // This screen is pumped with the real clock, so the row has to sit in
      // the week the screen will actually ask for — week-scoped reads mean an
      // unanchored or stale row is simply not returned.
      'week_start': plannerWeekValueFor(DateTime.now()),
      'day_index': 0,
      'slot_index': 0,
      'title': 'Planned Earlier',
      'source': 'Custom AI Craving',
      'aisle_items': const [],
      'recipe_payload': null,
      'is_cooked': false,
    });

    await tester.pumpWidget(_wrap(backend));
    await tester.pumpAndSettle();

    expect(find.text('Planned Earlier'), findsOneWidget);
    expect(backend.listCalls, 1, reason: 'no stale read, so no re-read');
  });

  testWidgets('a placement made after the load is persisted and stays visible',
      (tester) async {
    final backend = FakeWeeklyPlanBackend();

    await tester.pumpWidget(_wrap(backend));
    await tester.pumpAndSettle();

    WeeklyPlannerIntentService.instance.queueAddMeal(
      dayIndex: 0,
      recipe: testRecipe('Late Dish'),
      source: kFromSavedMealSource,
    );
    await tester.pumpAndSettle();

    expect(find.text('Late Dish'), findsOneWidget);
    expect(backend.rows, hasLength(1));
    expect(backend.listCalls, 1,
        reason: 'nothing was discarded, so nothing needs re-reading');
  });
}
