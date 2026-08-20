import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:optimeal/screens/home_dashboard_screen.dart';
import 'package:optimeal/screens/my_recipes_screen.dart';
import 'package:optimeal/screens/onboarding_screen.dart';
import 'package:optimeal/screens/techniques_media_screen.dart';
import 'package:optimeal/screens/weekly_planner_screen.dart';
import 'package:optimeal/screens/paywall_screen.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/screens/recipe_details_screen.dart';
import 'package:optimeal/screens/profile_screen.dart';
import 'package:optimeal/screens/fridge_clearer_screen.dart';
import 'package:optimeal/screens/culinary_masterclass_screen.dart';
import 'package:optimeal/state/user_profile_controller.dart';

/// GoRouter configuration for app navigation
///
/// This uses go_router for declarative routing, which provides:
/// - Type-safe navigation
/// - Deep linking support (web URLs, app links)
/// - Easy route parameters
/// - Navigation guards and redirects
///
/// To add a new route:
/// 1. Add a route constant to AppRoutes below
/// 2. Add a GoRoute to the routes list
/// 3. Navigate using context.go() or context.push()
/// 4. Use context.pop() to go back.
/// App-wide [RouteObserver], so a screen that stays mounted underneath
/// pushed routes (e.g. [HomeDashboardScreen], which is never disposed by
/// simply pushing Fridge Clearer / Cook Mode on top of it) can still learn
/// when it becomes the top-of-stack route again via [RouteAware.didPopNext].
/// Registered on the router below; subscribe with
/// `routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute)`.
final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();

class AppRouter {
  /// The most recently created router, so code outside the widget tree
  /// (currently: the fridge nudge notification's tap/action handler, see
  /// FridgeNudgeService) can navigate without a BuildContext. Set at the
  /// end of [createRouter], which MyApp calls once at startup.
  static GoRouter? lastRouter;

  static GoRouter createRouter(UserProfileController profile) {
    final router = GoRouter(
      initialLocation:
          profile.isOnboarded ? AppRoutes.home : AppRoutes.onboarding,
      refreshListenable: profile,
      observers: [routeObserver],
      redirect: (context, state) {
        if (!profile.isLoaded) return null;
        final isOnboarding = state.matchedLocation == AppRoutes.onboarding;
        if (!profile.isOnboarded && !isOnboarding) return AppRoutes.onboarding;
        if (profile.isOnboarded && isOnboarding) return AppRoutes.home;
        return null;
      },
      routes: [
        GoRoute(
          path: AppRoutes.onboarding,
          name: 'onboarding',
          builder: (context, state) => const OnboardingScreen(),
        ),
        GoRoute(
          path: AppRoutes.home,
          name: 'home',
          // The bottom-nav shell (MainLayout) is gone — Home is now a plain
          // route rendering the one-screen hub directly. Weekly Planner and
          // Techniques, which used to be tab indexes inside that shell, are
          // ordinary pushed routes below.
          pageBuilder: (context, state) => const NoTransitionPage(
            child: HomeDashboardScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.weeklyPlan,
          name: 'weekly_plan',
          builder: (context, state) => const WeeklyPlannerScreen(),
        ),
        GoRoute(
          path: AppRoutes.techniques,
          name: 'techniques',
          builder: (context, state) => const TechniquesMediaScreen(),
        ),
        GoRoute(
          path: AppRoutes.myRecipes,
          name: 'my_recipes',
          builder: (context, state) => const MyRecipesScreen(),
        ),
        GoRoute(
          path: AppRoutes.recipe,
          name: 'recipe',
          // `extra` carries the recipe to show (My recipes taps a saved card
          // through here). Without one this falls back to the screen's
          // long-standing static demo body.
          builder: (context, state) {
            final extra = state.extra;
            return RecipeDetailsScreen(
              recipe: extra is CookModeRecipePayload ? extra : null,
            );
          },
        ),
        GoRoute(
          path: AppRoutes.onePanCookingRoadmap,
          name: 'one_pan_cooking_roadmap',
          builder: (context, state) {
            final extra = state.extra;
            if (extra is ActiveCookSession) {
              return OnePanCookingRoadmapScreen(resumeSession: extra);
            }
            if (extra is CookModeLaunchRequest) {
              return OnePanCookingRoadmapScreen(
                recipe: extra.recipe,
                surface: extra.surface,
                isReCook: extra.isReCook,
              );
            }
            return const OnePanCookingRoadmapScreen();
          },
        ),
        GoRoute(
          path: AppRoutes.aiFridgeScrapGenerator,
          name: 'ai_fridge_scrap_generator',
          // No longer a bottom-nav tab (docs/decisions_2026-08-17.md item
          // 5) — pushed directly instead, same as fridgeClearerPicker.
          // This is also the deep-link target for the "Fridge Clearer"
          // fridge-nudge notification action.
          builder: (context, state) => const FridgeClearerScreen(),
        ),
        GoRoute(
          path: AppRoutes.fridgeClearerPicker,
          name: 'fridge_clearer_picker',
          builder: (context, state) =>
              const FridgeClearerScreen(returnCookModePayload: true),
        ),
        GoRoute(
          path: AppRoutes.profile,
          name: 'profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: AppRoutes.culinaryMasterclass,
          name: 'culinary_masterclass',
          builder: (context, state) => const CulinaryMasterclassScreen(),
        ),
        GoRoute(
          path: AppRoutes.paywall,
          name: 'paywall',
          builder: (context, state) => const PaywallScreen(),
        ),
      ],
    );
    lastRouter = router;
    return router;
  }
}

/// Route path constants
class AppRoutes {
  static const String home = '/';

  static const String onboarding = '/onboarding';
  static const String recipe = '/recipe';
  static const String weeklyPlan = '/weekly-plan';

  /// Techniques & Media. Was bottom-nav tab index 2 ('/tab/2') until the nav
  /// bar was removed; now a plain depth-1 route off the Home hub.
  static const String techniques = '/techniques';

  /// Placeholder destination behind the Home hub's "My recipes" tile — the
  /// route is live now, the real screen ships later. See MyRecipesScreen.
  static const String myRecipes = '/my-recipes';
  static const String onePanCookingRoadmap = '/one-pan-cooking-roadmap';
  static const String aiFridgeScrapGenerator = '/ai-fridge-scrap-generator';
  static const String fridgeClearerPicker = '/fridge-clearer-picker';

  /// Deep-link target for the fridge nudge notification's "AI generator"
  /// action: lands on Home, which opens the Custom AI Recipe Creator sheet
  /// on first frame when it sees this query param (see
  /// HomeDashboardScreen._checkDeepLinkIntent). Not a distinct GoRoute —
  /// '/' already matches it, the query param is read from GoRouterState.
  static const String homeOpenAiGenerator = '/?open=ai_generator';
  static const String profile = '/profile';
  static const String culinaryMasterclass = '/culinary-masterclass';
  static const String paywall = '/paywall';
}
