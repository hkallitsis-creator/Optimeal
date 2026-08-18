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
