import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/models/planner_slot_ref.dart';
import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/models/recipe_origin.dart';
import 'package:optimeal/models/recipe_scale.dart';
import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/screens/recipe_details_screen.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/services/overview_route_registry.dart';
import 'package:optimeal/services/saved_recipes_service.dart';
import 'package:optimeal/services/upgrade_nudge_gate.dart';
import 'package:optimeal/services/user_profile_service.dart';
import 'package:optimeal/state/ingredient_prep_controller.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/widgets/recipe_overview_body.dart';

import '../support/fake_saved_recipes_backend.dart';

/// Audit findings H-1, H-2, M-1, M-2 (docs/audit_2026-08-23.md) — the
/// back-from-Cook-Mode round trip and the servings fallbacks.

CookModeRecipePayload _recipe({String title = 'Chicken Traybake'}) =>
    CookModeRecipePayload(
      title: title,
      ingredients: const ['200 g potatoes'],
      steps: const [
        CookModeStepPayload(
          title: 'Heat the oil',
          heat: 'medium',
          durationMinutes: 5,
          bullets: ['do the thing'],
        ),
        CookModeStepPayload(
          title: 'Roast it',
          heat: 'medium',
          durationMinutes: 20,
          bullets: ['do the other thing'],
        ),
      ],
      kitchenGear: const ['Pan'],
      structuredIngredients: [
        RecipeIngredient(name: 'potatoes', amount: 200, unit: 'g'),
      ],
      basePortions: 2,
      origin: RecipeOrigin.fridgeClearer,
    );

/// A router with the two real routes the round trip uses, built exactly the
/// way lib/nav.dart builds them, so the pop-vs-replace behaviour under test
/// is the shipping stack shape and not a harness artifact.
Widget _routerHost(CookModeRecipePayload recipe) {
  final service = SavedRecipesService(backend: FakeSavedRecipesBackend());
  final profile = UserProfileController(UserProfileService());
  final router = GoRouter(
    initialLocation: AppRoutes.recipe,
    routes: [
      GoRoute(
        path: AppRoutes.recipe,
        builder: (context, state) {
          final extra = state.extra;
          return RecipeDetailsScreen(
            recipe: extra is CookModeRecipePayload ? extra : recipe,
            service: service,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.onePanCookingRoadmap,
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
              plannerSlot: extra.plannerSlot,
              servings: extra.servings,
            );
          }
          return const OnePanCookingRoadmapScreen();
        },
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const Scaffold(body: Text('home stub')),
      ),
    ],
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => IngredientPrepController()),
      ChangeNotifierProvider.value(value: profile),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// The same host, but starting inside Cook Mode from a planner-style direct
/// launch (no overview underneath) — the replace branch.
Widget _plannerLaunchHost(CookModeRecipePayload recipe) {
  final service = SavedRecipesService(backend: FakeSavedRecipesBackend());
  final profile = UserProfileController(UserProfileService());
  final router = GoRouter(
    initialLocation: AppRoutes.onePanCookingRoadmap,
    routes: [
      GoRoute(
        path: AppRoutes.onePanCookingRoadmap,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is ActiveCookSession) {
            return OnePanCookingRoadmapScreen(resumeSession: extra);
          }
          return OnePanCookingRoadmapScreen(
            recipe: recipe,
            plannerSlot: const PlannerSlotRef(
              weekStart: '2026-08-17',
              dayIndex: 2,
              slotIndex: 0,
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.recipe,
        builder: (context, state) {
          final extra = state.extra;
          return RecipeDetailsScreen(
            recipe: extra is CookModeRecipePayload ? extra : null,
            service: service,
          );
        },
      ),
    ],
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => IngredientPrepController()),
      ChangeNotifierProvider.value(value: profile),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Finder _inCookMode(Finder inner) => find.descendant(
    of: find.byType(OnePanCookingRoadmapScreen), matching: inner);

Future<void> _advanceTwoSteps(WidgetTester tester) async {
  // Overview CTA → Cook Mode's pre-cook body → Start → Step 1 (mise) →
  // Step 2 → Step 3.
  await tester.tap(find.text('Start cooking'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start Cooking').last);
  await tester.pumpAndSettle();
  expect(find.textContaining('Step 1 of 3'), findsOneWidget);
  await tester.tap(find.text("Board's clear — heat goes on"));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Next step'));
  await tester.pumpAndSettle();
  expect(find.textContaining('Step 3 of 3'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OverviewRouteRegistry.resetForTest();
    UpgradeNudgeGate.resetForTest();
  });

  group('H-2 — never two overviews of one recipe on the stack', () {
    testWidgets('back POPS to the overview that launched the cook',
        (tester) async {
      await tester.pumpWidget(_routerHost(_recipe()));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeDetailsScreen), findsOneWidget);

      await _advanceTwoSteps(tester);
      // The launcher overview is still mounted below Cook Mode (offstage) —
      // exactly one instance in the whole tree.
      expect(find.byType(RecipeDetailsScreen, skipOffstage: false),
          findsOneWidget);

      await tester.tap(_inCookMode(find.byIcon(Icons.arrow_back)).first);
      await tester.pumpAndSettle();

      // Popped, not replaced: ONE overview in the entire tree (on- or
      // offstage), zero Cook Modes — the old behaviour left
      // [overview(old), overview(new)] here.
      expect(find.byType(RecipeDetailsScreen, skipOffstage: false),
          findsOneWidget);
      expect(find.byType(OnePanCookingRoadmapScreen, skipOffstage: false),
          findsNothing);
    });

    testWidgets(
        'a launch with no overview underneath still gets a fresh overview '
        '(replace branch unchanged)', (tester) async {
      await tester.pumpWidget(_plannerLaunchHost(_recipe()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start Cooking').last);
      await tester.pumpAndSettle();

      await tester.tap(_inCookMode(find.byIcon(Icons.arrow_back)).first);
      await tester.pumpAndSettle();

      expect(find.byType(RecipeDetailsScreen, skipOffstage: false),
          findsOneWidget);
      expect(find.byType(OnePanCookingRoadmapScreen, skipOffstage: false),
          findsNothing);
    });
  });

  group('H-1 — the exact audit repro, end to end', () {
    testWidgets(
        'overview → Start cooking → two steps → back → Start cooking '
        'RESUMES at step 3 with the same session', (tester) async {
      await tester.pumpWidget(_routerHost(_recipe()));
      await tester.pumpAndSettle();

      await _advanceTwoSteps(tester);

      final storage = CookSessionStorageService();
      final before = await storage.loadActiveSession();
      expect(before, isNotNull);
      expect(before!.activeStepIndex, 2);
      final beforeKey = SavedRecipesService.recipeKeyFor(before.recipe.title);

      // Back — pops to the launcher overview (H-2). The audit's "→ back →"
      // second press is now unreachable-by-construction: there is no second
      // overview to fall through to, which is the fix.
      await tester.tap(_inCookMode(find.byIcon(Icons.arrow_back)).first);
      await tester.pumpAndSettle();

      // The overview KNOWS the session exists (cookLog subscription): its
      // Start cooking resumes rather than calling saveActiveSession over a
      // live session.
      await tester.tap(find.text('Start cooking'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Step 3 of 3'), findsOneWidget,
          reason: 'resume at the stored step, never a restart at Step 1');

      final after = await storage.loadActiveSession();
      expect(after, isNotNull);
      expect(SavedRecipesService.recipeKeyFor(after!.recipe.title), beforeKey,
          reason: 'same session identity (there is no id field; the '
              'normalized recipe key is the identity resume matching uses)');
      expect(after.activeStepIndex, 2,
          reason: 'the live session was never overwritten back to Step 1');
      expect(after.completedSteps, {0, 1});
    });

    testWidgets(
        'planner detour: back → fresh overview → resume keeps PlannerSlotRef',
        (tester) async {
      await tester.pumpWidget(_plannerLaunchHost(_recipe()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start Cooking').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Board's clear — heat goes on"));
      await tester.pumpAndSettle();

      await tester.tap(_inCookMode(find.byIcon(Icons.arrow_back)).first);
      await tester.pumpAndSettle();
      expect(find.byType(RecipeDetailsScreen), findsOneWidget);

      await tester.tap(find.text('Start cooking'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Step 2 of 3'), findsOneWidget);

      final session = await CookSessionStorageService().loadActiveSession();
      expect(session?.plannerSlot?.dayIndex, 2,
          reason: 'slot attribution survives the detour');
      expect(session?.plannerSlot?.weekStart, '2026-08-17');
    });

    test('the overview subscribes to the cook-store signal (source pin)', () {
      // Structural companion to the widget tests above: the subscription is
      // the mechanism, and it must not quietly revert to an initState-only
      // read — that exact shape was audit finding H-1.
      final code =
          File('lib/screens/recipe_details_screen.dart').readAsStringSync();
      expect(code.contains('AppDataChanges.cookLog.listen'), isTrue);
      expect(code.contains('_cookLogSub?.cancel()'), isTrue);
    });
  });

  group('M-1 — the stepper is locked while a session is in progress', () {
    testWidgets('disabled at the locked N; re-enables when the session ends',
        (tester) async {
      await tester.pumpWidget(_routerHost(_recipe()));
      await tester.pumpAndSettle();

      // No session: live stepper at the default (basePortions = 2).
      expect(find.text('Serves 2'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Serves 3'), findsOneWidget);

      // Start at 3, advance, come back: locked at 3, stepper dead.
      await tester.tap(find.text('Start cooking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start Cooking').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Board's clear — heat goes on"));
      await tester.pumpAndSettle();
      await tester.tap(_inCookMode(find.byIcon(Icons.arrow_back)).first);
      await tester.pumpAndSettle();

      expect(find.text('Serves 3'), findsOneWidget,
          reason: 'shows the locked N, not a live default it would ignore');
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Serves 4'), findsNothing,
          reason: 'quantities are locked from Start cooking (signed)');

      // The body widget itself carries the flag.
      final body = tester.widget<RecipeOverviewBody>(
          find.byType(RecipeOverviewBody));
      expect(body.enabled, isFalse);

      // Session ends → the cookLog signal re-reads → stepper live again.
      await CookSessionStorageService().clearActiveSession();
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Serves 4'), findsOneWidget,
          reason: 're-enables only when no session is active');
    });
  });

  group('M-2 — one null-servings fallback for every Cook Mode entry', () {
    test('the resolver implements the signed precedence', () {
      // launch → household (caller gates onboarded) → basePortions → 1
      expect(
          resolveCookModeServings(
              launchServings: 4,
              profileHouseholdServings: 5,
              recipeBasePortions: 2),
          4);
      expect(
          resolveCookModeServings(
              profileHouseholdServings: 5, recipeBasePortions: 2),
          5);
      expect(resolveCookModeServings(recipeBasePortions: 2), 2);
      expect(resolveCookModeServings(), 1);
    });

    testWidgets(
        'a launch that bypassed the overview: mise pill and the mid-cook '
        'ingredients pane agree', (tester) async {
      // basePortions 2, no launch servings, profile not onboarded →
      // both surfaces resolve to 2. Before the fix the pill consulted the
      // profile while _ingredients used basePortions — two chains.
      await tester.pumpWidget(_plannerLaunchHost(_recipe()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start Cooking').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Serves 2'), findsOneWidget);
      expect(find.textContaining('200 g'), findsWidgets,
          reason: 'ingredient scale matches the pill (200 g at base 2)');
    });
  });
}
