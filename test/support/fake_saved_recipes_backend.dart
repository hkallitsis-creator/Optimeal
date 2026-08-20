import 'package:optimeal/models/recipe_origin.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/saved_recipes_service.dart';

/// In-memory stand-in for `public.saved_recipes`, shared by the service tests
/// and the widget tests.
///
/// Enforces the two things the real table does — the `(user_id, recipe_key)`
/// unique constraint, and that an upsert does NOT reset `saved_at` — so tests
/// exercise real behaviour rather than a permissive fake. No Supabase client,
/// no live database, no anonymous sign-in.
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

/// A minimal but structurally real recipe payload for widget tests.
CookModeRecipePayload testRecipe(
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
