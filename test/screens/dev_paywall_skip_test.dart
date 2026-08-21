import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/config/app_environment.dart';
import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/paywall_screen.dart';
import 'package:optimeal/services/user_profile_service.dart';
import 'package:optimeal/state/ingredient_prep_controller.dart';
import 'package:optimeal/state/user_profile_controller.dart';

/// Dev builds never show the paywall — they route straight through.
///
/// Guarded at the ROUTE, not at the two call sites (onboarding's "skip",
/// `UpgradePromptSheet`'s CTA), so a third entry point added later cannot
/// forget the check. `kIsDevEnvironment` is a compile-time constant resolved
/// from `OPTIMEAL_ENV`, which defaults to `dev` — so this test runs in the dev
/// arm unless the suite is deliberately run with
/// `--dart-define=OPTIMEAL_ENV=prod`, and asserts the other arm's contract
/// rather than skipping.

Widget _app() {
  final profile = UserProfileController(UserProfileService());
  final router = AppRouter.createRouter(profile);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => IngredientPrepController()),
      ChangeNotifierProvider.value(value: profile),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('navigating to /paywall lands on Home in a dev build',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    AppRouter.lastRouter!.go(AppRoutes.paywall);
    await tester.pumpAndSettle();

    if (kIsDevEnvironment) {
      expect(find.byType(PaywallScreen), findsNothing,
          reason: 'dev builds route straight through');
      expect(AppRouter.lastRouter!.state.uri.path, AppRoutes.home);
    } else {
      // Release behaviour is unchanged: the paywall is a real destination.
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(AppRouter.lastRouter!.state.uri.path, AppRoutes.paywall);
    }
  });

  test('the paywall route carries a redirect at all', () {
    // Cheap structural guard: if someone deletes the redirect, the widget test
    // above still passes in a prod-flavoured run, and nothing else would
    // notice. This fails either way.
    final router =
        AppRouter.createRouter(UserProfileController(UserProfileService()));
    final paywall = router.configuration.routes
        .expand((r) => [r, ...r.routes])
        .whereType<GoRoute>()
        .firstWhere((r) => r.path == AppRoutes.paywall);
    expect(paywall.redirect, isNotNull);
  });
}
