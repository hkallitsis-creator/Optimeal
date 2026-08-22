import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/services/entitlement_service.dart';
import 'package:optimeal/services/upgrade_nudge_gate.dart';

/// Entitlement is a property of the **environment**, not of the build mode.
///
/// This shipped the other way round and it mattered: device testing uses a
/// **release-mode** APK pointed at dev, `isPro()` bypassed only under
/// `kDebugMode`, and the dev paywall redirect had already removed the
/// mock-purchase path. So the one configuration Harris actually tests on hit
/// the free-tier caps with no unlock route at all.
void main() {
  group('the bypass matrix', () {
    // kIsDevEnvironment and kDebugMode are both compile-time constants, so a
    // test process cannot vary them. The decision is therefore a pure
    // function and this is the matrix that matters.

    test('dev environment + release mode → entitled', () {
      // The configuration on Harris's phone. This is the case that was broken.
      expect(
        EntitlementService.entitlementBypassFor(
            isDevEnvironment: true, isDebugMode: false),
        isTrue,
      );
    });

    test('dev environment + debug mode → entitled', () {
      expect(
        EntitlementService.entitlementBypassFor(
            isDevEnvironment: true, isDebugMode: true),
        isTrue,
      );
    });

    test('release environment + release mode → NOT entitled, caps live', () {
      expect(
        EntitlementService.entitlementBypassFor(
            isDevEnvironment: false, isDebugMode: false),
        isFalse,
        reason: 'release behaviour must be completely unchanged',
      );
    });

    test('release environment + debug mode → entitled (developer machine)', () {
      // kDebugMode survives as an additional OR, never as the only path.
      expect(
        EntitlementService.entitlementBypassFor(
            isDevEnvironment: false, isDebugMode: true),
        isTrue,
      );
    });
  });

  group('the gate-site census', () {
    // Every entitlement-gated site in the app, by class. A gate that does not
    // route through EntitlementService.isPro() is invisible to the
    // environment bypass, which is exactly the failure this whole change
    // exists to prevent — so a NEW call site fails this test until it is
    // added here deliberately.
    const expectedSites = <String>{
      // _FridgeClearerScreenState — weekly generation cap
      'lib/screens/fridge_clearer_screen.dart',
      // _HomeDashboardScreenState — post-cook upgrade nudge
      'lib/screens/home_dashboard_screen.dart',
      // _CustomAiRecipeCreatorSheetState — lifetime free-uses cap
      'lib/widgets/custom_ai_recipe_creator_sheet.dart',
    };

    test('every isPro() caller is on the list', () {
      final found = <String>{};
      final libDir = Directory('lib');

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final rel = entity.path.replaceAll(r'\', '/');
        // The service defining isPro() is not a gate site.
        if (rel.endsWith('services/entitlement_service.dart')) continue;

        final source = entity.readAsStringSync();
        // Strip line comments so a doc reference is not read as a call.
        final code = source
            .split('\n')
            .map((l) {
              final trimmed = l.trimLeft();
              if (trimmed.startsWith('//')) return '';
              final i = l.indexOf('//');
              return i == -1 ? l : l.substring(0, i);
            })
            .join('\n');

        if (code.contains('.isPro()')) found.add(rel);
      }

      expect(found, expectedSites,
          reason: 'a new entitlement gate appeared, or one moved. Every gate '
              'must call EntitlementService.isPro() and be listed here.');
    });

    test('the usage-cap service is only reached from listed gate sites', () {
      final found = <String>{};
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final rel = entity.path.replaceAll(r'\', '/');
        if (rel.endsWith('services/usage_cap_service.dart')) continue;
        if (entity.readAsStringSync().contains('UsageCapService.instance')) {
          found.add(rel);
        }
      }

      // Home does not count usage; it only reads entitlement for the nudge.
      expect(found, {
        'lib/screens/fridge_clearer_screen.dart',
        'lib/widgets/custom_ai_recipe_creator_sheet.dart',
      });
    });
  });

  group('the post-cook nudge is once per cook', () {
    setUp(UpgradeNudgeGate.resetForTest);
    tearDown(UpgradeNudgeGate.resetForTest);

    test('one cook owes at most one nudge, however often it is scheduled', () {
      const token = 'cook_1';
      UpgradeNudgeGate.schedulePostCookNudge(token);
      UpgradeNudgeGate.schedulePostCookNudge(token);
      UpgradeNudgeGate.schedulePostCookNudge(token);

      expect(UpgradeNudgeGate.consumePendingPostCookNudge(), isTrue);
      expect(UpgradeNudgeGate.consumePendingPostCookNudge(), isFalse);

      // The completion sequence running again for the SAME cook — a resumed
      // session, a retried write — must not re-arm it.
      UpgradeNudgeGate.schedulePostCookNudge(token);
      expect(UpgradeNudgeGate.hasPendingPostCookNudge, isFalse);
      expect(UpgradeNudgeGate.consumePendingPostCookNudge(), isFalse);
    });

    test('a genuinely new cook does owe a new nudge', () {
      UpgradeNudgeGate.schedulePostCookNudge('cook_1');
      expect(UpgradeNudgeGate.consumePendingPostCookNudge(), isTrue);

      UpgradeNudgeGate.schedulePostCookNudge('cook_2');
      expect(UpgradeNudgeGate.consumePendingPostCookNudge(), isTrue);
    });

    test('a rebuild storm cannot show it twice', () {
      UpgradeNudgeGate.schedulePostCookNudge('cook_1');
      final results = [
        for (var i = 0; i < 50; i++)
          UpgradeNudgeGate.consumePendingPostCookNudge(),
      ];
      expect(results.where((r) => r).length, 1);
    });
  });
}
