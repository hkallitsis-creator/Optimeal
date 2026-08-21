import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/home_dashboard_screen.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/services/data_change_signal.dart';
import 'package:optimeal/services/ledger_service.dart';
import 'package:optimeal/services/user_profile_service.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/widgets/app_bottom_sheet.dart';

import '../support/fake_saved_recipes_backend.dart';

/// Symptom A, device report 2026-08-22: "Home shows the old rescue count after
/// a completed cook; correct only after restart."
///
/// Home is mounted underneath every cook, so nothing rebuilds it. Its only
/// refresh used to be [RouteAware.didPopNext] — and the second group below
/// pins down why that can never be enough: the post-cook exit is a verdict
/// sheet's CTA doing `context.pop()` then `context.go('/')`, and a Navigator
/// page that still has a modal (pageless) route attached when the page list
/// shrinks is resolved as *complete*, not *pop*. [RouteObserver] forwards only
/// `didPop`, so the route underneath is told nothing at all.

const _weeklyEventsPrefsKey = 'waste_ledger_weekly_events_v1';

/// Writes local weekly ledger events in the exact shape
/// `LedgerService._encodeWeeklyEvents` produces, so these tests read back
/// through the real [LedgerService.getWeeklySummary].
void _seedWeeklyRescues(List<String> ingredients) {
  SharedPreferences.setMockInitialValues({
    _weeklyEventsPrefsKey: jsonEncode([
      {'ts': DateTime.now().toIso8601String(), 'ingredients': ingredients},
    ]),
  });
}

Future<void> _addWeeklyRescues(List<String> ingredients) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_weeklyEventsPrefsKey);
  final events = raw == null ? [] : (jsonDecode(raw) as List);
  events.add({
    'ts': DateTime.now().toIso8601String(),
    'ingredients': ingredients,
  });
  await prefs.setString(_weeklyEventsPrefsKey, jsonEncode(events));
}

/// Stands in for Cook Mode: a pushed page whose only exit is a bottom sheet
/// CTA, which is precisely the shape of the real post-cook verdict sheets.
class _CookStub extends StatelessWidget {
  const _CookStub();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => AppBottomSheet.show<void>(
              context: context,
              builder: (ctx) => TextButton(
                onPressed: () {
                  ctx.pop();
                  ctx.go(AppRoutes.home);
                },
                child: const Text('Back to Home'),
              ),
            ),
            child: const Text('finish cook'),
          ),
        ),
      );
}

GoRouter _buildRouter() => GoRouter(
      initialLocation: AppRoutes.home,
      observers: [routeObserver],
      routes: [
        GoRoute(
          path: AppRoutes.home,
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: HomeDashboardScreen()),
        ),
        GoRoute(
          path: AppRoutes.onePanCookingRoadmap,
          builder: (context, state) => const _CookStub(),
        ),
      ],
    );

Widget _wrap(GoRouter router) => ChangeNotifierProvider<UserProfileController>(
      create: (_) => UserProfileController(UserProfileService()),
      child: MaterialApp.router(routerConfig: router),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the rescue strip is refreshed by the write, not by the navigation',
      () {
    testWidgets('a ledger change reaches Home while it is mounted underneath',
        (tester) async {
      _seedWeeklyRescues(['Zucchini']);

      await tester.pumpWidget(_wrap(_buildRouter()));
      await tester.pumpAndSettle();
      expect(find.text('1 ingredient rescued this week'), findsOneWidget);

      final homeState = tester.state(find.byType(HomeDashboardScreen));

      // What a completed cook does: the local weekly store changes, then
      // LedgerService announces it.
      await _addWeeklyRescues(['Feta', 'Spinach']);
      AppDataChanges.ledger.notify();
      await tester.pumpAndSettle();

      expect(find.text('3 ingredients rescued this week'), findsOneWidget);
      expect(tester.state(find.byType(HomeDashboardScreen)), same(homeState),
          reason: 'Home was refreshed in place, not remounted');
    });

    testWidgets(
        'the count is current after a cook that exits through a sheet CTA',
        (tester) async {
      _seedWeeklyRescues(['Zucchini']);

      final router = _buildRouter();
      await tester.pumpWidget(_wrap(router));
      await tester.pumpAndSettle();
      expect(find.text('1 ingredient rescued this week'), findsOneWidget);

      router.push(AppRoutes.onePanCookingRoadmap);
      await tester.pumpAndSettle();

      // The cook completes: ledger written, then the verdict sheet opens.
      await _addWeeklyRescues(['Feta', 'Spinach']);
      AppDataChanges.ledger.notify();
      await tester.tap(find.text('finish cook'));
      await tester.pumpAndSettle();

      // Its single CTA: dismiss the sheet, then go Home.
      await tester.tap(find.text('Back to Home'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeDashboardScreen), findsOneWidget);
      expect(find.text('3 ingredients rescued this week'), findsOneWidget);
    });
  });

  group('the resume banner rides the same signal', () {
    testWidgets('a session saved while Home is mounted raises the banner',
        (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(_wrap(_buildRouter()));
      await tester.pumpAndSettle();
      expect(find.text('Pick up where you left off'), findsNothing);

      await CookSessionStorageService().saveActiveSession(
        recipe: testRecipe('Half-cooked Dish'),
        cookStarted: true,
        cookPaused: true,
        activeStepIndex: 0,
        completedSteps: const <int>{},
        activeRemaining: const Duration(minutes: 3),
        currentPortions: 2,
        surface: CookModeSurface.fridgeClearer,
        isReCook: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Pick up where you left off'), findsOneWidget);
      expect(find.text('Half-cooked Dish'), findsOneWidget);
    });
  });

  group('why didPopNext alone could never have carried this', () {
    testWidgets(
        'context.go past a page with a modal sheet attached delivers no '
        'RouteAware notification at all', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final probe = _RouteAwareProbe();

      final router = GoRouter(
        initialLocation: AppRoutes.home,
        observers: [routeObserver],
        routes: [
          GoRoute(
            path: AppRoutes.home,
            pageBuilder: (context, state) =>
                NoTransitionPage(child: _ProbeHost(probe: probe)),
          ),
          GoRoute(
            path: AppRoutes.onePanCookingRoadmap,
            builder: (context, state) => const _CookStub(),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      router.push(AppRoutes.onePanCookingRoadmap);
      await tester.pumpAndSettle();

      // Control: an ordinary pop DOES notify.
      router.pop();
      await tester.pumpAndSettle();
      expect(probe.popNextCount, 1);

      // The real post-cook shape: sheet open, CTA pops it and immediately
      // replaces the stack. The exiting page still owns a pageless route, so
      // the Navigator completes it instead of popping it.
      router.push(AppRoutes.onePanCookingRoadmap);
      await tester.pumpAndSettle();
      await tester.tap(find.text('finish cook'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to Home'));
      await tester.pumpAndSettle();

      expect(probe.popNextCount, 1,
          reason: 'no didPopNext for a go() past an attached sheet — this is '
              'the framework behaviour that made the rescue strip stale');
    });
  });
}

class _RouteAwareProbe {
  int popNextCount = 0;
}

class _ProbeHost extends StatefulWidget {
  const _ProbeHost({required this.probe});
  final _RouteAwareProbe probe;

  @override
  State<_ProbeHost> createState() => _ProbeHostState();
}

class _ProbeHostState extends State<_ProbeHost> with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(
        this, ModalRoute.of(context)! as PageRoute<dynamic>);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() => widget.probe.popNextCount++;

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('probe home')));
}
