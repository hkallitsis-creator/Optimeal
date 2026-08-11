import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// True if the current user has active Pro entitlement.
  Future<bool> isPro() async {
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
