import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/home_dashboard_screen.dart';
import 'package:optimeal/services/user_profile_service.dart';
import 'package:optimeal/state/user_profile_controller.dart';

/// Minimal GoRouter harness for Home. Deliberately does NOT use the real
/// [AppRouter.createRouter] — that pulls in onboarding redirects and every
/// other screen. What matters here is that Home is built underneath a real
/// GoRouter/ModalRoute, which is exactly the condition that produced the
/// live `dependOnInheritedWidgetOfExactType<_ModalScopeStatus>() was called
/// before _HomeDashboardScreenState.initState() completed` crash.
Widget _wrapHome({String initialLocation = AppRoutes.home}) {
  final controller = UserProfileController(UserProfileService());
  final router = GoRouter(
    initialLocation: initialLocation,
    observers: [routeObserver],
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeDashboardScreen(),
      ),
    ],
  );
  return ChangeNotifierProvider<UserProfileController>.value(
    value: controller,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HomeDashboardScreen — first frame', () {
    testWidgets('builds inside a GoRouter without throwing on first frame',
        (tester) async {
      await tester.pumpWidget(_wrapHome());
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
          _wrapHome(initialLocation: AppRoutes.homeOpenAiGenerator));
      expect(tester.takeException(), isNull);
      expect(find.byType(HomeDashboardScreen), findsOneWidget);
    });
  });
}
