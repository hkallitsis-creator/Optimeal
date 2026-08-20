import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/models/cook_mode_recipe_codec.dart';
import 'package:optimeal/models/recipe_origin.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/services/saved_recipes_service.dart';

/// In-memory stand-in for `public.saved_recipes`. Deliberately enforces the
/// same two things the real table does — the `(user_id, recipe_key)` unique
/// constraint, and that an upsert does NOT reset `saved_at` — so the tests
/// below exercise the service's real behaviour rather than a permissive fake.
///
/// No Supabase client, no live database, no anonymous sign-in (which is
/// currently disabled on dev anyway).
class FakeSavedRecipesBackend implements SavedRecipesBackend {
  FakeSavedRecipesBackend({this.currentUserId = 'user-1'});

  @override
  String? currentUserId;

  final List<Map<String, dynamic>> rows = [];

  int upsertCalls = 0;
  int touchCalls = 0;
  bool throwOnWrite = false;

  int _nextId = 1;

  int _indexOf(String userId, String recipeKey) => rows.indexWhere(
      (r) => r['user_id'] == userId && r['recipe_key'] == recipeKey);

  @override
  Future<void> upsert(Map<String, dynamic> row) async {
    upsertCalls++;
    if (throwOnWrite) throw Exception('write failed');
    final i = _indexOf(row['user_id'] as String, row['recipe_key'] as String);
    if (i == -1) {
      rows.add({
        'id': 'row-${_nextId++}',
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        ...row,
      });
    } else {
      // Real upsert semantics: only the provided columns are written, so
      // saved_at survives untouched.
      rows[i] = {...rows[i], ...row};
    }
  }

  @override
  Future<void> deleteByKey({
    required String userId,
    required String recipeKey,
  }) async {
    if (throwOnWrite) throw Exception('write failed');
    rows.removeWhere(
        (r) => r['user_id'] == userId && r['recipe_key'] == recipeKey);
  }

  @override
  Future<bool> touch({
    required String userId,
    required String recipeKey,
    required DateTime at,
  }) async {
    touchCalls++;
    if (throwOnWrite) throw Exception('write failed');
    final i = _indexOf(userId, recipeKey);
    if (i == -1) return false;
    rows[i]['last_touched_at'] = at.toIso8601String();
    return true;
  }

  @override
  Future<List<Map<String, dynamic>>> listForUser(String userId) async {
    return rows
        .where((r) => r['user_id'] == userId)
        .map((r) => Map<String, dynamic>.from(r))
        .toList(growable: false);
  }
}

CookModeRecipePayload _recipe(
  String title, {
  RecipeOrigin? origin,
  List<String>? entered,
}) {
  return CookModeRecipePayload(
    title: title,
    ingredients: const ['300g Zucchini', '100g Feta'],
    steps: const [
      CookModeStepPayload(
        title: 'Sear',
        heat: 'medium_high',
        durationMinutes: 6,
        bullets: ['Do not crowd the pan.'],
      ),
    ],
    kitchenGear: const ['1 Pan'],
    basePortions: 2,
    origin: origin,
    originEnteredIngredients: entered,
  );
}

SavedRecipesService _service(FakeSavedRecipesBackend backend) =>
    SavedRecipesService(
      backend: backend,
      sessionStorage: CookSessionStorageService(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('recipe identity', () {
    test('the key is the title trimmed, lowercased, whitespace-collapsed', () {
      expect(SavedRecipesService.recipeKeyFor('  Zucchini   Skillet '),
          'zucchini skillet');
      expect(SavedRecipesService.recipeKeyFor('ZUCCHINI SKILLET'),
          SavedRecipesService.recipeKeyFor('zucchini skillet'));
    });
  });

  group('save / unsave / isSaved', () {
    test('save writes one row and isSaved reports it', () async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);

      expect(await service.save(_recipe('Zucchini Skillet')), isTrue);
      expect(backend.rows, hasLength(1));
      expect(
          await service
              .isSaved(SavedRecipesService.recipeKeyFor('Zucchini Skillet')),
          isTrue);
    });

    test('re-saving updates in place instead of creating a duplicate',
        () async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);

      await service.save(_recipe('Zucchini Skillet'));
      final savedAtFirst = backend.rows.single['saved_at'];
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await service.save(_recipe('  zucchini   SKILLET  '));

      expect(backend.rows, hasLength(1),
          reason: 'one row per (user, recipe identity)');
      expect(backend.rows.single['saved_at'], savedAtFirst,
          reason: 're-saving is not saving for the first time again');
    });

    test('re-saving counts as activity and moves last_touched_at forward',
        () async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);

      await service.save(_recipe('Zucchini Skillet'));
      final first =
          DateTime.parse(backend.rows.single['last_touched_at'] as String);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await service.save(_recipe('Zucchini Skillet'));
      final second =
          DateTime.parse(backend.rows.single['last_touched_at'] as String);

      expect(second.isAfter(first), isTrue);
    });

    test('unsave removes the row and is idempotent', () async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);
      final key = SavedRecipesService.recipeKeyFor('Zucchini Skillet');

      await service.save(_recipe('Zucchini Skillet'));
      expect(await service.unsave(key), isTrue);
      expect(backend.rows, isEmpty);
      expect(await service.unsave(key), isTrue,
          reason: 'unsaving something not saved is not an error');
      expect(await service.isSaved(key), isFalse);
    });

    test('an untitled recipe is refused rather than written', () async {
      final backend = FakeSavedRecipesBackend();
      expect(await _service(backend).save(_recipe('   ')), isFalse);
      expect(backend.upsertCalls, 0);
    });

    test('with no signed-in user everything degrades to false, never throws',
        () async {
      final backend = FakeSavedRecipesBackend(currentUserId: null);
      final service = _service(backend);

      expect(await service.save(_recipe('Zucchini Skillet')), isFalse);
      expect(await service.unsave('zucchini skillet'), isFalse);
      expect(await service.isSaved('zucchini skillet'), isFalse);
      expect(
          await service.onRecipeCooked(_recipe('Zucchini Skillet')), isFalse);
      expect(await service.listSavedRecipes(), isEmpty);
      expect(backend.upsertCalls, 0);
    });

    test('a failing write returns false rather than throwing', () async {
      final backend = FakeSavedRecipesBackend()..throwOnWrite = true;
      final service = _service(backend);
      expect(await service.save(_recipe('Zucchini Skillet')), isFalse);
      expect(await service.unsave('zucchini skillet'), isFalse);
    });
  });

  group('provenance', () {
    test('a Fridge Clearer recipe keeps its origin in the column and payload',
        () async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);

      await service.save(_recipe('Zucchini Skillet',
          origin: RecipeOrigin.fridgeClearer, entered: ['Zucchini', 'Feta']));

      final row = backend.rows.single;
      expect(row['origin'], 'fridgeClearer');
      expect((row['recipe_payload'] as Map)['origin'], 'fridgeClearer');

      final saved = (await service.listSavedRecipes()).single;
      expect(saved.origin, RecipeOrigin.fridgeClearer);
      expect(saved.isFridgeRescue, isTrue,
          reason: 'the leaf badge reads off the origin column');
      expect(saved.recipe.originEnteredIngredients, ['Zucchini', 'Feta']);
    });

    test('a custom craving does not earn the leaf badge', () async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);

      await service.save(
          _recipe('Carbonara', origin: RecipeOrigin.customAiRecipeCreator));

      final saved = (await service.listSavedRecipes()).single;
      expect(saved.origin, RecipeOrigin.customAiRecipeCreator);
      expect(saved.isFridgeRescue, isFalse);
    });

    test('a recipe with no recorded origin does not earn the badge', () async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);

      await service.save(_recipe('Old Recipe'));

      final saved = (await service.listSavedRecipes()).single;
      expect(saved.origin, isNull);
      expect(saved.isFridgeRescue, isFalse);
    });

    test(
        'the saved payload can be reopened and rescheduled without regenerating',
        () async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);
      final original = _recipe('Zucchini Skillet',
          origin: RecipeOrigin.fridgeClearer, entered: ['Zucchini']);

      await service.save(original);
      final saved = (await service.listSavedRecipes()).single;

      expect(saved.recipe.title, original.title);
      expect(saved.recipe.ingredients, original.ingredients);
      expect(saved.recipe.steps, hasLength(original.steps.length));
      expect(saved.recipe.steps.first.title, original.steps.first.title);
      expect(saved.recipe.basePortions, original.basePortions);
      expect(saved.recipe.kitchenGear, original.kitchenGear);
      // The exact shape user_meal_plans.recipe_payload takes, so scheduling
      // it into the planner is a straight hand-off.
      expect(cookModeRecipeToJson(saved.recipe)['title'], original.title);
    });
  });

  group('promote from history', () {
    test('saving a past cook keeps its provenance intact', () async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);

      final entry = RecentlyCookedEntry(
        recipe: _recipe('Zucchini Skillet',
            origin: RecipeOrigin.fridgeClearer, entered: ['Zucchini']),
        cookedAt: DateTime.now().subtract(const Duration(days: 3)),
        source: CookSessionStorageService.declaredKeySource,
      );

      expect(await service.saveFromHistory(entry), isTrue);

      final saved = (await service.listSavedRecipes()).single;
      expect(saved.origin, RecipeOrigin.fridgeClearer);
      expect(saved.isFridgeRescue, isTrue);
      expect(saved.recipe.originEnteredIngredients, ['Zucchini']);
    });
  });

  group('touch on cook', () {
    test('cooking a saved recipe moves it to the top of the list', () async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);

      await service.save(_recipe('First'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await service.save(_recipe('Second'));

      expect((await service.listSavedRecipes()).map((s) => s.title),
          ['Second', 'First']);

      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(await service.onRecipeCooked(_recipe('First')), isTrue);

      expect((await service.listSavedRecipes()).map((s) => s.title),
          ['First', 'Second'],
          reason: 'most recent activity first');
    });

    test('cooking an unsaved recipe does not save it', () async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);

      expect(await service.onRecipeCooked(_recipe('Never Saved')), isFalse);
      expect(backend.rows, isEmpty);
      expect(backend.upsertCalls, 0);
      expect(backend.touchCalls, 1);
    });
  });

  group('watchSavedRecipes', () {
    test('emits the current list immediately, then again after each mutation',
        () async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);
      await service.save(_recipe('First'));

      final emissions = <List<String>>[];
      final sub = service
          .watchSavedRecipes()
          .listen((list) => emissions.add(list.map((s) => s.title).toList()));

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(emissions, [
        ['First']
      ]);

      await service.save(_recipe('Second'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(emissions.last, ['Second', 'First']);

      await service.unsave(SavedRecipesService.recipeKeyFor('Second'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(emissions.last, ['First']);

      await sub.cancel();
      await service.dispose();
    });

    test('is always sorted by last_touched_at desc regardless of backend order',
        () async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);

      // Rows handed back in deliberately wrong order.
      backend.rows.addAll([
        {
          'id': 'a',
          'user_id': 'user-1',
          'recipe_key': 'oldest',
          'title': 'Oldest',
          'recipe_payload': cookModeRecipeToJson(_recipe('Oldest')),
          'origin': null,
          'saved_at': '2026-08-01T10:00:00Z',
          'last_touched_at': '2026-08-01T10:00:00Z',
        },
        {
          'id': 'b',
          'user_id': 'user-1',
          'recipe_key': 'newest',
          'title': 'Newest',
          'recipe_payload': cookModeRecipeToJson(_recipe('Newest')),
          'origin': null,
          'saved_at': '2026-08-01T10:00:00Z',
          'last_touched_at': '2026-08-19T10:00:00Z',
        },
      ]);

      expect((await service.listSavedRecipes()).map((s) => s.title),
          ['Newest', 'Oldest']);
    });

    test('one unparseable row is skipped, not fatal to the whole shelf',
        () async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);
      await service.save(_recipe('Good'));
      backend.rows.add({
        'id': 'bad',
        'user_id': 'user-1',
        'recipe_key': 'bad',
        'title': 'Bad',
        'recipe_payload': {'title': 'Bad'}, // no steps -> undecodable
        'origin': null,
        'saved_at': '2026-08-01T10:00:00Z',
        'last_touched_at': '2026-08-01T10:00:00Z',
      });

      final list = await service.listSavedRecipes();
      expect(list.map((s) => s.title), ['Good']);
    });

    test('rows belonging to another user are never returned', () async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);
      await service.save(_recipe('Mine'));
      backend.rows.add({
        'id': 'other',
        'user_id': 'user-2',
        'recipe_key': 'theirs',
        'title': 'Theirs',
        'recipe_payload': cookModeRecipeToJson(_recipe('Theirs')),
        'origin': null,
        'saved_at': '2026-08-01T10:00:00Z',
        'last_touched_at': '2026-08-19T10:00:00Z',
      });

      expect((await service.listSavedRecipes()).map((s) => s.title), ['Mine']);
    });
  });

  group('recently-cooked read model', () {
    Future<void> seedHistory(int count) async {
      final storage = CookSessionStorageService();
      for (var i = 0; i < count; i++) {
        await storage.addRecentlyCooked(_recipe('Dish $i'));
      }
    }

    test('is capped at kRecentlyCookedReadModelLimit', () async {
      await seedHistory(14);
      final recent = await _service(FakeSavedRecipesBackend()).recentlyCooked();
      expect(recent.length, kRecentlyCookedReadModelLimit);
    });

    test('is newest first', () async {
      await seedHistory(3);
      final recent = await _service(FakeSavedRecipesBackend()).recentlyCooked();
      expect(recent.first.recipe.title, 'Dish 2');
    });

    test('is empty, not an error, when nothing has been cooked', () async {
      expect(
          await _service(FakeSavedRecipesBackend()).recentlyCooked(), isEmpty);
    });
  });

  group('derived cook counts (not stored on saved_recipes)', () {
    test('timesCooked counts matching history entries', () async {
      final storage = CookSessionStorageService();
      await storage.addRecentlyCooked(_recipe('Zucchini Skillet'));

      final service = _service(FakeSavedRecipesBackend());
      final key = SavedRecipesService.recipeKeyFor('Zucchini Skillet');

      expect(await service.timesCooked(key), 1);
      expect(await service.hasBeenCooked(key), isTrue);
    });

    test('a saved-but-never-cooked recipe reports zero', () async {
      final service = _service(FakeSavedRecipesBackend());
      await service.save(_recipe('Never Cooked'));
      final key = SavedRecipesService.recipeKeyFor('Never Cooked');

      expect(await service.timesCooked(key), 0);
      expect(await service.hasBeenCooked(key), isFalse);
    });

    test('the count is never written to the saved row', () async {
      final backend = FakeSavedRecipesBackend();
      final service = _service(backend);
      await service.save(_recipe('Zucchini Skillet'));

      final row = backend.rows.single;
      expect(row.containsKey('times_cooked'), isFalse);
      expect(row.containsKey('cooked_count'), isFalse);
      expect(row.containsKey('has_been_cooked'), isFalse);
    });
  });
}
