import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/home_dashboard_screen.dart';
import 'package:optimeal/screens/my_recipes_screen.dart';
import 'package:optimeal/services/user_profile_service.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/widgets/branded_avatar_glyph.dart';
import 'package:optimeal/widgets/home_glyph_button.dart';

/// Stand-in for a real destination screen. The point of the navigation tests
/// below is that Home hands GoRouter the right *path* — the destinations
/// themselves (Weekly Planner, Techniques, Fridge Clearer) drag in Supabase
/// and are covered by their own surfaces.
class _StubScreen extends StatelessWidget {
  const _StubScreen(this.label);
  final String label;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}

/// Minimal GoRouter harness. Deliberately does NOT use the real
/// [AppRouter.createRouter] — that pulls in the onboarding redirect and every
/// screen in the app. What matters is that Home is built underneath a real
/// GoRouter/ModalRoute (the condition that produced the live
/// `dependOnInheritedWidgetOfExactType<_ModalScopeStatus>()` crash) and that
/// its taps resolve against the real [AppRoutes] constants.
GoRouter _buildRouter({String initialLocation = AppRoutes.home}) {
  return GoRouter(
    initialLocation: initialLocation,
    observers: [routeObserver],
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.weeklyPlan,
        builder: (context, state) => const _StubScreen('weekly'),
      ),
      GoRoute(
        path: AppRoutes.techniques,
        builder: (context, state) => const _StubScreen('techniques'),
      ),
      // The real placeholder — it is the deliverable for this route, and it
      // has no heavyweight dependencies.
      GoRoute(
        path: AppRoutes.myRecipes,
        builder: (context, state) => const MyRecipesScreen(),
      ),
      GoRoute(
        path: AppRoutes.aiFridgeScrapGenerator,
        builder: (context, state) => const _StubScreen('fridge clearer'),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) => const _StubScreen('profile'),
      ),
      // Stands in for a depth-2 screen (recipe details / Cook Mode): its app
      // bar leading slot is the same shared BackWithHomeLeading those screens
      // now use.
      GoRoute(
        path: AppRoutes.recipe,
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            leadingWidth: kBackWithHomeLeadingWidth,
            leading: BackWithHomeLeading(
              back: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            title: const Text('recipe details'),
          ),
        ),
      ),
    ],
  );
}

Widget _wrap(GoRouter router) {
  return ChangeNotifierProvider<UserProfileController>.value(
    value: UserProfileController(UserProfileService()),
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Location of the top-most route. `currentConfiguration.uri` reports the
/// base location and does not move for an imperative `push`, which is what
/// every Home tap does — `last.matchedLocation` is the one that does.
String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.last.matchedLocation;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HomeDashboardScreen — first frame', () {
    testWidgets('builds inside a GoRouter without throwing on first frame',
        (tester) async {
      await tester.pumpWidget(_wrap(_buildRouter()));
      // First frame only — the crash was raised during initState, so it would
      // surface before any settle.
      expect(tester.takeException(), isNull);
      expect(find.byType(HomeDashboardScreen), findsOneWidget);

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'builds without throwing when landed on with the deep-link query param',
        (tester) async {
      // The '/?open=ai_generator' fridge-nudge deep link is the exact path
      // that read GoRouterState during initState.
      await tester.pumpWidget(
          _wrap(_buildRouter(initialLocation: AppRoutes.homeOpenAiGenerator)));
      expect(tester.takeException(), isNull);
      expect(find.byType(HomeDashboardScreen), findsOneWidget);
    });
  });

  group('HomeDashboardScreen — hub zones', () {
    testWidgets('renders all six zones', (tester) async {
      await tester.pumpWidget(_wrap(_buildRouter()));
      await tester.pumpAndSettle();

      // 1 — greeting (two lines) + profile avatar
      expect(find.text('Hello, Chef.'), findsOneWidget);
      expect(find.text('What are we cooking?'), findsOneWidget);
      expect(find.byType(BrandedAvatarGlyph), findsOneWidget);

      // 2 — Fridge Clearer hero
      expect(find.text('Fridge Clearer'), findsOneWidget);
      expect(find.text('Cook what you already have.'), findsOneWidget);

      // 3 — custom recipe slim row
      expect(find.text('Cook something specific'), findsOneWidget);

      // 4 — three tiles
      expect(find.text('Weekly'), findsOneWidget);
      expect(find.text('My recipes'), findsOneWidget);
      expect(find.text('Techniques'), findsOneWidget);

      // 6 — rescue strip
      expect(find.textContaining('rescued this week'), findsOneWidget);
      expect(find.text('how?'), findsOneWidget);
    });

    testWidgets('has exactly one flexible gap and does not scroll',
        (tester) async {
      await tester.pumpWidget(_wrap(_buildRouter()));
      await tester.pumpAndSettle();

      expect(find.byType(Spacer), findsOneWidget);
      expect(find.byType(Scrollable), findsNothing);
    });

    testWidgets('fits a small phone viewport without overflowing',
        (tester) async {
      // No-scroll means overflow is a real failure mode, not cosmetic.
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(_buildRouter()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('has no bottom nav bar anywhere in the tree', (tester) async {
      await tester.pumpWidget(_wrap(_buildRouter()));
      await tester.pumpAndSettle();

      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      final scaffold = tester.widget<Scaffold>(find.descendant(
          of: find.byType(HomeDashboardScreen),
          matching: find.byType(Scaffold)));
      expect(scaffold.bottomNavigationBar, isNull);
    });

    testWidgets('carries none of the cut cards', (tester) async {
      await tester.pumpWidget(_wrap(_buildRouter()));
      await tester.pumpAndSettle();

      for (final cut in const [
        'Recipe Library',
        'Weekly Plan & Shop',
        'Recently Cooked',
        'This Week',
        'Omnivore',
        'Get an idea',
        'Technique of the Week',
      ]) {
        expect(find.text(cut), findsNothing, reason: '"$cut" should be cut');
      }
      expect(find.textContaining('saved favorites'), findsNothing);
    });
  });

  group('HomeDashboardScreen — navigation', () {
    Future<void> tapAndExpect(
      WidgetTester tester,
      String label,
      String expectedPath,
    ) async {
      final router = _buildRouter();
      await tester.pumpWidget(_wrap(router));
      await tester.pumpAndSettle();

      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(_location(router), expectedPath);
    }

    testWidgets('hero opens Fridge Clearer', (tester) async {
      await tapAndExpect(
          tester, 'Fridge Clearer', AppRoutes.aiFridgeScrapGenerator);
    });

    testWidgets('Weekly tile opens the Weekly Planner', (tester) async {
      await tapAndExpect(tester, 'Weekly', AppRoutes.weeklyPlan);
    });

    testWidgets('My recipes tile opens the My recipes placeholder',
        (tester) async {
      final router = _buildRouter();
      await tester.pumpWidget(_wrap(router));
      await tester.pumpAndSettle();

      await tester.tap(find.text('My recipes'));
      await tester.pumpAndSettle();

      expect(_location(router), AppRoutes.myRecipes);
      expect(find.byType(MyRecipesScreen), findsOneWidget);
    });

    testWidgets('Techniques tile opens Techniques', (tester) async {
      await tapAndExpect(tester, 'Techniques', AppRoutes.techniques);
    });

    testWidgets('avatar opens Profile', (tester) async {
      final router = _buildRouter();
      await tester.pumpWidget(_wrap(router));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BrandedAvatarGlyph));
      await tester.pumpAndSettle();

      expect(_location(router), AppRoutes.profile);
    });

    testWidgets('slim row opens the custom recipe creator sheet',
        (tester) async {
      final router = _buildRouter();
      await tester.pumpWidget(_wrap(router));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cook something specific'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // A sheet, not a route push — Home stays the current location.
      expect(_location(router), AppRoutes.home);
      expect(find.text('What are you in the mood for?'), findsOneWidget);
    });

    testWidgets('"how?" opens the ledger explainer', (tester) async {
      final router = _buildRouter();
      await tester.pumpWidget(_wrap(router));
      await tester.pumpAndSettle();

      await tester.tap(find.text('how?'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('This tracks real fridge rescues'),
          findsOneWidget);
      // Sheet rule: an explicit X in addition to drag-down / barrier tap.
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('depth-2 home glyph lands on Home in one navigation',
        (tester) async {
      final router = _buildRouter(initialLocation: AppRoutes.recipe);
      await tester.pumpWidget(_wrap(router));
      await tester.pumpAndSettle();

      expect(find.byType(HomeGlyphButton), findsOneWidget);

      await tester.tap(find.byType(HomeGlyphButton));
      await tester.pumpAndSettle();

      expect(_location(router), AppRoutes.home);
      expect(find.byType(HomeDashboardScreen), findsOneWidget);
    });
  });
}
