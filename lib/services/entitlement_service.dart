import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/config/app_environment.dart';

/// RevenueCat entitlement identifier for Pro access. Must match the
/// entitlement configured in the RevenueCat dashboard once a real project
/// exists — see CLAUDE.md "Monetization / paywall tier structure".
const String kProEntitlementId = 'pro';

/// RevenueCat public SDK API keys. Deliberately left empty — Harris has not
/// created a real Apple Developer / Play Console / RevenueCat account yet
/// (deferred until closer to real-tester distribution, see CLAUDE.md).
/// While empty, [EntitlementService] falls back to a local mock so all
/// gating logic is still fully buildable and testable.
const String kRevenueCatIosApiKey = '';
const String kRevenueCatAndroidApiKey = '';

/// Local mock flag, shared with [PaywallScreen]'s existing (also mocked)
/// purchase flow, so "purchasing" in dev actually flips entitlement state
/// end to end without a real store behind it.
const String kMockIsSubscribedKey = 'isSubscribed';

/// Single source of truth for "is this user Pro" across the app.
///
/// Uses real RevenueCat entitlement state once [kRevenueCatIosApiKey] /
/// [kRevenueCatAndroidApiKey] are filled in with real keys. Until then,
/// every method falls back to a local mock flag — this is intentional
/// sandbox behavior, not a bug, while real store accounts are deferred.
class EntitlementService {
  EntitlementService._();
  static final EntitlementService instance = EntitlementService._();

  bool _configured = false;

  bool get _hasRealKeys => kRevenueCatIosApiKey.isNotEmpty || kRevenueCatAndroidApiKey.isNotEmpty;

  /// Call once at app startup. No-op (and safe to call) while no real
  /// RevenueCat keys are configured.
  Future<void> configure() async {
    if (!_hasRealKeys || _configured) return;
    final apiKey = defaultTargetPlatform == TargetPlatform.iOS ? kRevenueCatIosApiKey : kRevenueCatAndroidApiKey;
    if (apiKey.isEmpty) return;
    try {
      await Purchases.setLogLevel(LogLevel.debug);
      await Purchases.configure(PurchasesConfiguration(apiKey));
      _configured = true;
    } catch (e) {
      debugPrint('EntitlementService.configure failed (continuing in mock mode): $e');
    }
  }

  /// Whether entitlement is bypassed outright, before any store or mock
  /// lookup. Pure, and parameterised, so the matrix that matters can actually
  /// be tested — [kIsDevEnvironment] and [kDebugMode] are both compile-time
  /// constants, so a test process cannot vary them.
  ///
  /// **Entitlement is a property of the ENVIRONMENT, not of the build mode.**
  /// That distinction was not academic: a **release-mode** APK pointed at dev
  /// — which is exactly what device testing uses, per the build/install pair
  /// in CLAUDE.md — bypassed nothing, hit the free-tier caps, and had no way
  /// out, because the dev paywall redirect had already removed the
  /// mock-purchase path. Two weeks of device testing would have run into a
  /// wall on day one.
  ///
  /// `kDebugMode` stays as an additional OR, never as the only path: a debug
  /// build pointed at prod is still a developer's machine.
  ///
  /// Release environment behaviour is **unchanged** — both constants are
  /// false there, so this folds away and the real checks below run.
  @visibleForTesting
  static bool entitlementBypassFor({
    required bool isDevEnvironment,
    required bool isDebugMode,
  }) =>
      isDevEnvironment || isDebugMode;

  /// True if the current user has active Pro entitlement.
  ///
  /// Every caller already gates usage caps AND the paywall behind
  /// `if (!isPro) { ... }` (Fridge Clearer weekly cap, Custom AI Recipe
  /// Creator's free-lifetime limit, the post-cook upgrade nudge), so
  /// short-circuiting here unlocks all of them at once. That is why this is
  /// the only place the bypass lives — see
  /// `test/services/entitlement_gate_test.dart`, which enumerates the gate
  /// sites and fails when a new one appears that does not route through here.
  Future<bool> isPro() async {
    if (entitlementBypassFor(
      isDevEnvironment: kIsDevEnvironment,
      isDebugMode: kDebugMode,
    )) {
      return true;
    }
    if (_hasRealKeys && _configured) {
      try {
        final info = await Purchases.getCustomerInfo();
        return info.entitlements.active.containsKey(kProEntitlementId);
      } catch (e) {
        debugPrint('EntitlementService.isPro RevenueCat check failed, falling back to mock: $e');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kMockIsSubscribedKey) ?? false;
  }

  /// Mock-mode only: flips the local Pro flag. Real purchases go through
  /// RevenueCat's own purchase flow instead once configured. Used by
  /// [PaywallScreen]'s placeholder purchase handler.
  Future<void> setMockPro(bool isPro) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kMockIsSubscribedKey, isPro);
  }
}
