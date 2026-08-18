import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/models/user_profile.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/confidence_climb_service.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';

CookModeRecipePayload _recipe(String title, List<String> curriculumLessonIds) => CookModeRecipePayload(
      title: title,
      ingredients: const ['Salt'],
      steps: const [CookModeStepPayload(title: 'Cook', heat: 'medium', durationMinutes: 5, bullets: ['Cook it.'])],
      curriculumLessonIds: curriculumLessonIds,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ConfidenceClimbService comfortable-technique persistence', () {
    test('loadComfortableTechniqueIds starts empty', () async {
      final service = ConfidenceClimbService();
      expect(await service.loadComfortableTechniqueIds(), isEmpty);
    });

    test('markComfortable then loadComfortableTechniqueIds contains it', () async {
      final service = ConfidenceClimbService();
      await service.markComfortable('braising');
      expect(await service.loadComfortableTechniqueIds(), {'braising'});
    });

    test('markNotComfortable reverses a previous markComfortable', () async {
      final service = ConfidenceClimbService();
      await service.markComfortable('braising');
      await service.markNotComfortable('braising');
      expect(await service.loadComfortableTechniqueIds(), isEmpty);
    });

    test('markNotComfortable on a technique never marked is a harmless no-op', () async {
      final service = ConfidenceClimbService();
      await service.markNotComfortable('braising');
      expect(await service.loadComfortableTechniqueIds(), isEmpty);
    });
  });

  group('ConfidenceClimbService.evaluate — repeat/comfortable technique detection', () {
    test('a technique appearing only once in history (this cook) is not a repeat', () async {
      final sessionStorage = CookSessionStorageService();
      await sessionStorage.addRecentlyCooked(_recipe('Braised Chicken', ['braising']));

      final service = ConfidenceClimbService(sessionStorage: sessionStorage);
      final result = await service.evaluate(
        justCookedTechniqueIds: ['braising'],
        currentConfidence: KitchenConfidence.beginner,
      );

      expect(result.repeatTechniqueIds, isEmpty);
    });

    test('a technique appearing twice in history (a prior different dish) is a repeat', () async {
      final sessionStorage = CookSessionStorageService();
      // Two different dishes teaching the same technique — addRecentlyCooked
      // dedupes by title, so distinct titles are required to actually
      // accumulate two entries.
      await sessionStorage.addRecentlyCooked(_recipe('Braised Chicken', ['braising']));
      await sessionStorage.addRecentlyCooked(_recipe('Braised Pork', ['braising']));

      final service = ConfidenceClimbService(sessionStorage: sessionStorage);
      final result = await service.evaluate(
        justCookedTechniqueIds: ['braising'],
        currentConfidence: KitchenConfidence.beginner,
      );

      expect(result.repeatTechniqueIds, {'braising'});
    });

    test('a comfortable technique among justCookedTechniqueIds is reported back', () async {
      final sessionStorage = CookSessionStorageService();
      await sessionStorage.addRecentlyCooked(_recipe('Braised Chicken', ['braising']));

      final service = ConfidenceClimbService(sessionStorage: sessionStorage);
      await service.markComfortable('braising');

      final result = await service.evaluate(
        justCookedTechniqueIds: ['braising', 'sauteing'],
        currentConfidence: KitchenConfidence.beginner,
      );

      expect(result.comfortableTechniqueIds, {'braising'});
    });

    test('an unstamped (pre-F11) legacy history entry is excluded from repeat counting', () async {
      // Simulates a pre-migration cook_session_history_v1 record: same
      // shape CookSessionStorageService writes, but with no "source" key
      // at all — exactly what a real record written before device-test
      // round F11 looks like on disk. Written directly to SharedPreferences
      // rather than via addRecentlyCooked, since that method always stamps
      // new writes now.
      final legacyEntry = {
        'recipe': {
          'title': 'Legacy Braised Lamb',
          'ingredients': ['Salt'],
          'steps': [
            {
              'title': 'Cook',
              'heat': 'medium',
              'durationMinutes': 5,
              'bullets': ['Cook it.'],
            }
          ],
          'curriculumLessonIds': ['braising'],
        },
        'cookedAt': DateTime.now().toIso8601String(),
        // No 'source' key — the pre-F11 shape.
      };
      SharedPreferences.setMockInitialValues({
        'cook_session_history_v1': jsonEncode([legacyEntry]),
      });

      final sessionStorage = CookSessionStorageService();
      // A stamped entry for the same technique, via the normal write path.
      await sessionStorage.addRecentlyCooked(_recipe('Braised Pork (new)', ['braising']));

      final service = ConfidenceClimbService(sessionStorage: sessionStorage);
      final result = await service.evaluate(
        justCookedTechniqueIds: ['braising'],
        currentConfidence: KitchenConfidence.beginner,
      );

      // Only 1 stamped entry exists (this cook's own) — the unstamped
      // legacy entry must not count toward "prior completions", so this
      // is NOT a repeat despite 2 raw entries existing in storage.
      expect(result.repeatTechniqueIds, isEmpty);
    });

    test('empty justCookedTechniqueIds returns an empty evaluation, including empty sets', () async {
      final service = ConfidenceClimbService();
      final result = await service.evaluate(
        justCookedTechniqueIds: const [],
        currentConfidence: KitchenConfidence.beginner,
      );

      expect(result.repeatTechniqueIds, isEmpty);
      expect(result.comfortableTechniqueIds, isEmpty);
      expect(result.celebrationLine, isNull);
      expect(result.tierUpTarget, isNull);
    });
  });
}
