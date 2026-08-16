import 'package:go_router/go_router.dart';
import 'package:optimeal/screens/main_layout.dart';
import 'package:optimeal/screens/onboarding_screen.dart';
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
class AppRouter {
  static GoRouter createRouter(UserProfileController profile) => GoRouter(
        initialLocation: profile.isOnboarded ? AppRoutes.home : AppRoutes.onboarding,
        refreshListenable: profile,
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
            pageBuilder: (context, state) => const NoTransitionPage(
              child: MainLayout(),
            ),
          ),
          GoRoute(
            path: AppRoutes.homeTabPath,
            name: 'home_tab',
            pageBuilder: (context, state) {
              final index = int.tryParse(state.pathParameters['index'] ?? '') ?? 0;
              return NoTransitionPage(child: MainLayout(currentIndex: index));
            },
          ),
          GoRoute(
            path: AppRoutes.weeklyPlan,
            name: 'weekly_plan',
            // Keep bottom navigation persistent when navigating by route.
            pageBuilder: (context, state) => const NoTransitionPage(child: MainLayout(currentIndex: 2)),
          ),
          GoRoute(
            path: AppRoutes.recipe,
            name: 'recipe',
            builder: (context, state) => const RecipeDetailsScreen(),
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
            // Keep bottom navigation persistent when navigating by route.
            pageBuilder: (context, state) => const NoTransitionPage(child: MainLayout(currentIndex: 1)),
          ),
          GoRoute(
            path: AppRoutes.fridgeClearerPicker,
            name: 'fridge_clearer_picker',
            builder: (context, state) => const FridgeClearerScreen(returnCookModePayload: true),
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
}

/// Route path constants
class AppRoutes {
  static const String home = '/';
  static const String homeTabPath = '/tab/:index';
  static String homeTab(int index) => '/tab/$index';

  static const String onboarding = '/onboarding';
  static const String recipe = '/recipe';
  static const String weeklyPlan = '/weekly-plan';
  static const String onePanCookingRoadmap = '/one-pan-cooking-roadmap';
  static const String aiFridgeScrapGenerator = '/ai-fridge-scrap-generator';
  static const String fridgeClearerPicker = '/fridge-clearer-picker';
  static const String profile = '/profile';
  static const String culinaryMasterclass = '/culinary-masterclass';
  static const String paywall = '/paywall';
}