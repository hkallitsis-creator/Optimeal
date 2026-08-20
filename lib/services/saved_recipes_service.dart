import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:optimeal/models/cook_mode_recipe_codec.dart';
import 'package:optimeal/models/recipe_origin.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';

/// How many past cooks the "My recipes" screen shows in its recently-cooked
/// strip. Read-only over data that already exists — no new table, no new
/// capture. Ten is a deliberate cap: [CookSessionStorageService] keeps 20
/// entries of history, and showing all of them turns a "pick up where you
/// left off" list into an archive.
const int kRecentlyCookedReadModelLimit = 10;

/// One row of `public.saved_recipes`, decoded.
class SavedRecipe {
  const SavedRecipe({
    required this.id,
    required this.recipeKey,
    required this.title,
    required this.recipe,
    required this.origin,
    required this.savedAt,
    required this.lastTouchedAt,
  });

  final String id;
  final String recipeKey;
  final String title;

  /// The full payload, good enough to reopen recipe details or schedule the
  /// recipe into the Weekly Planner with no regeneration.
  final CookModeRecipePayload recipe;

  /// Provenance, read from the dedicated `origin` column rather than out of
  /// [recipe] — the column is the leaf badge's source of truth. The two are
  /// always written together by [SavedRecipesService.save], so they cannot
  /// disagree.
  final RecipeOrigin? origin;

  final DateTime savedAt;
  final DateTime lastTouchedAt;

  /// Whether this recipe earns the leaf badge.
  bool get isFridgeRescue => origin?.isRescueEligible ?? false;
}

/// The raw `saved_recipes` operations, abstracted so [SavedRecipesService]'s
/// real logic — identity, ordering, touch-on-activity, promote-from-history,
/// derived cook counts — is unit-testable without a live database or an
/// authenticated session. Same pattern as `ConnectivityMonitor` for
/// [LedgerSyncCoordinator] and `FridgeNudgeScheduler` for the nudges.
abstract class SavedRecipesBackend {
  /// Null when there is no signed-in user. Every method below is a no-op in
  /// that case; the service checks before calling.
  String? get currentUserId;

  /// Insert-or-update on the `(user_id, recipe_key)` unique constraint.
  /// Must not overwrite `saved_at` on an update — re-saving a recipe is not
  /// saving it again for the first time.
  Future<void> upsert(Map<String, dynamic> row);

  Future<void> deleteByKey({required String userId, required String recipeKey});

  /// Bumps `last_touched_at` only. Returns true if a row was actually
  /// matched, so callers can tell "touched" from "not saved".
  Future<bool> touch({
    required String userId,
    required String recipeKey,
    required DateTime at,
  });

  Future<List<Map<String, dynamic>>> listForUser(String userId);
}

class SupabaseSavedRecipesBackend implements SavedRecipesBackend {
  static const String table = 'saved_recipes';

  SupabaseClient get _db => Supabase.instance.client;

  /// Null when there is no signed-in user — and also when Supabase was never
  /// initialized, which `Supabase.instance` asserts on rather than returning
  /// null for. Every caller in [SavedRecipesService] reads this before doing
  /// anything and already treats null as "degrade quietly, save nothing", so
  /// an uninitialized client lands on exactly the right behaviour instead of
  /// throwing out of an unguarded getter.
  @override
  String? get currentUserId {
    try {
      return _db.auth.currentUser?.id;
    } catch (e) {
      debugPrint('SavedRecipesService: Supabase unavailable: $e');
      return null;
    }
  }

  @override
  Future<void> upsert(Map<String, dynamic> row) async {
    await _db.from(table).upsert(row, onConflict: 'user_id,recipe_key');
  }

  @override
  Future<void> deleteByKey({
    required String userId,
    required String recipeKey,
  }) async {
    await _db
        .from(table)
        .delete()
        .eq('user_id', userId)
        .eq('recipe_key', recipeKey);
  }

  @override
  Future<bool> touch({
    required String userId,
    required String recipeKey,
    required DateTime at,
  }) async {
    final updated = await _db
        .from(table)
        .update({'last_touched_at': at.toIso8601String()})
        .eq('user_id', userId)
        .eq('recipe_key', recipeKey)
        .select('id');
    return updated.isNotEmpty;
  }

  @override
  Future<List<Map<String, dynamic>>> listForUser(String userId) async {
    final rows = await _db
        .from(table)
        .select()
        .eq('user_id', userId)
        .order('last_touched_at', ascending: false);
    return rows
        .map((r) => Map<String, dynamic>.from(r))
        .toList(growable: false);
  }
}

/// Saved recipes — the "My recipes" data layer. The screen ships in a later
/// build; everything it needs is here.
///
/// A generated recipe has no server-side row and no server id, so identity is
/// [recipeKeyFor]: a normalized title. That is the same notion of "the same
/// recipe" [CookSessionStorageService] has always deduplicated its Recently
/// Cooked and cook-history lists on, so promoting a past cook into a saved
/// recipe lines up with the history entry it came from without a second
/// identity scheme.
class SavedRecipesService {
  SavedRecipesService({
    SavedRecipesBackend? backend,
    CookSessionStorageService? sessionStorage,
  })  : _backend = backend ?? SupabaseSavedRecipesBackend(),
        _sessionStorage = sessionStorage ?? CookSessionStorageService();

  static final SavedRecipesService instance = SavedRecipesService();

  final SavedRecipesBackend _backend;
  final CookSessionStorageService _sessionStorage;

  /// Fires after every successful mutation so [watchSavedRecipes] can re-read.
  /// Deliberately not a Supabase realtime subscription: saved recipes are
  /// single-user data that only ever changes because of something this app
  /// just did, so a local change signal is both sufficient and cheaper.
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Stable identity for a recipe with no server id: the title, trimmed,
  /// lowercased, with internal whitespace collapsed. Matches the
  /// `saved_recipes.recipe_key` column.
  static String recipeKeyFor(String title) =>
      title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Map<String, dynamic> _rowFor(CookModeRecipePayload recipe, String userId) => {
        'user_id': userId,
        'recipe_key': recipeKeyFor(recipe.title),
        'title': recipe.title.trim(),
        'recipe_payload': cookModeRecipeToJson(recipe),
        // Written from the same payload as `recipe_payload`, so the badge
        // column and the payload copy can never drift apart.
        'origin': recipe.origin?.name,
        'last_touched_at': DateTime.now().toUtc().toIso8601String(),
        // `saved_at` is deliberately absent: the column default handles the
        // insert, and an upsert must not reset it on a re-save.
      };

  /// Saves [recipe], provenance and all. Re-saving an already-saved recipe
  /// updates it in place and counts as activity ([SavedRecipe.lastTouchedAt]
  /// moves), rather than creating a second row.
  ///
  /// Returns false — without throwing — when there is no signed-in user or
  /// the write fails, matching how the rest of this project's Supabase
  /// services degrade.
  Future<bool> save(CookModeRecipePayload recipe) async {
    final userId = _backend.currentUserId;
    if (userId == null) {
      debugPrint('SavedRecipesService.save: not authenticated, skipping.');
      return false;
    }
    if (recipe.title.trim().isEmpty) {
      debugPrint(
          'SavedRecipesService.save: refusing to save an untitled recipe.');
      return false;
    }
    try {
      await _backend.upsert(_rowFor(recipe, userId));
      _changes.add(null);
      return true;
    } catch (e, st) {
      debugPrint('SavedRecipesService.save failed: $e\n$st');
      return false;
    }
  }

  /// Promote a past cook into a saved recipe.
  ///
  /// The stored cook session already carries the full payload including
  /// [CookModeRecipePayload.origin] and `originEnteredIngredients`, so a
  /// Fridge Clearer recipe saved from history keeps its leaf badge — no
  /// provenance is re-derived or guessed here.
  Future<bool> saveFromHistory(RecentlyCookedEntry entry) => save(entry.recipe);

  /// Removes the saved row. Idempotent: unsaving something that was never
  /// saved succeeds.
  Future<bool> unsave(String recipeKey) async {
    final userId = _backend.currentUserId;
    if (userId == null) return false;
    try {
      await _backend.deleteByKey(userId: userId, recipeKey: recipeKey);
      _changes.add(null);
      return true;
    } catch (e, st) {
      debugPrint('SavedRecipesService.unsave failed: $e\n$st');
      return false;
    }
  }

  Future<bool> isSaved(String recipeKey) async {
    final userId = _backend.currentUserId;
    if (userId == null) return false;
    try {
      final rows = await _backend.listForUser(userId);
      return rows.any((r) => r['recipe_key'] == recipeKey);
    } catch (e, st) {
      debugPrint('SavedRecipesService.isSaved failed: $e\n$st');
      return false;
    }
  }

  /// Touch-on-activity. Cooking a recipe is activity, so a saved recipe the
  /// user actually cooks floats back to the top of My recipes.
  ///
  /// A no-op for a recipe that isn't saved — cooking something does NOT
  /// silently save it. Returns whether a saved row was actually touched.
  Future<bool> onRecipeCooked(CookModeRecipePayload recipe) async {
    final userId = _backend.currentUserId;
    if (userId == null) return false;
    try {
      final touched = await _backend.touch(
        userId: userId,
        recipeKey: recipeKeyFor(recipe.title),
        at: DateTime.now().toUtc(),
      );
      if (touched) _changes.add(null);
      return touched;
    } catch (e, st) {
      debugPrint('SavedRecipesService.onRecipeCooked failed: $e\n$st');
      return false;
    }
  }

  /// The user's saved recipes, most recent activity first, re-emitted after
  /// every successful mutation. Emits the current list immediately on listen.
  ///
  /// Written with an explicit controller rather than `async*` so cancelling
  /// the subscription tears the inner listener down deterministically instead
  /// of leaving a generator parked on an event that may never arrive.
  Stream<List<SavedRecipe>> watchSavedRecipes() {
    late final StreamController<List<SavedRecipe>> controller;
    StreamSubscription<void>? changesSub;

    Future<void> emit() async {
      final list = await listSavedRecipes();
      if (controller.isClosed) return;
      controller.add(list);
    }

    controller = StreamController<List<SavedRecipe>>(
      onListen: () {
        changesSub = _changes.stream.listen((_) => emit());
        emit();
      },
      onCancel: () async {
        await changesSub?.cancel();
        changesSub = null;
      },
    );
    return controller.stream;
  }

  /// One-shot read of [watchSavedRecipes]'s current value.
  ///
  /// Sorted here rather than relying on the backend's ORDER BY: the ordering
  /// is part of this service's contract (the signed recency rule), so it is
  /// guaranteed regardless of which backend answered.
  Future<List<SavedRecipe>> listSavedRecipes() async {
    final userId = _backend.currentUserId;
    if (userId == null) return const [];
    try {
      final rows = await _backend.listForUser(userId);
      final decoded = <SavedRecipe>[];
      for (final row in rows) {
        final saved = _fromRow(row);
        // Skip rather than fail the whole list — one unparseable payload
        // must not empty the user's shelf.
        if (saved != null) decoded.add(saved);
      }
      decoded.sort((a, b) => b.lastTouchedAt.compareTo(a.lastTouchedAt));
      return decoded;
    } catch (e, st) {
      debugPrint('SavedRecipesService.listSavedRecipes failed: $e\n$st');
      return const [];
    }
  }

  static SavedRecipe? _fromRow(Map<String, dynamic> row) {
    try {
      final recipe = cookModeRecipeFromJson(row['recipe_payload']);
      if (recipe == null) return null;
      final savedAt = DateTime.tryParse('${row['saved_at'] ?? ''}');
      final lastTouchedAt =
          DateTime.tryParse('${row['last_touched_at'] ?? ''}');
      if (savedAt == null || lastTouchedAt == null) return null;
      return SavedRecipe(
        id: '${row['id'] ?? ''}',
        recipeKey: '${row['recipe_key'] ?? ''}',
        title: '${row['title'] ?? recipe.title}',
        recipe: recipe,
        origin: RecipeOrigin.fromName(row['origin']),
        savedAt: savedAt,
        lastTouchedAt: lastTouchedAt,
      );
    } catch (e) {
      debugPrint('SavedRecipesService: skipping unparseable saved row: $e');
      return null;
    }
  }

  // ---- Read models over existing data (no new table) --------------------

  /// The last [kRecentlyCookedReadModelLimit] cooks, newest first, for the
  /// upcoming My recipes screen. Straight read of the local cook history
  /// [CookSessionStorageService] already maintains.
  Future<List<RecentlyCookedEntry>> recentlyCooked() async {
    try {
      final history = await _sessionStorage.loadCookHistory();
      return history
          .take(kRecentlyCookedReadModelLimit)
          .toList(growable: false);
    } catch (e, st) {
      debugPrint('SavedRecipesService.recentlyCooked failed: $e\n$st');
      return const [];
    }
  }

  /// How many times this recipe has been cooked, DERIVED at read time from
  /// the cook history rather than stored on `saved_recipes`. Duplicating a
  /// counter into that table would create a second source of truth for
  /// something the ledger and cook-session stores already answer.
  ///
  /// Bounded by the local history cap, so this is "at least N" for a recipe
  /// cooked more times than history retains — which is all the UI needs
  /// ("cooked at least once", plus a count when it's small).
  Future<int> timesCooked(String recipeKey) async {
    try {
      final history = await _sessionStorage.loadCookHistory();
      return history
          .where((e) => recipeKeyFor(e.recipe.title) == recipeKey)
          .length;
    } catch (e, st) {
      debugPrint('SavedRecipesService.timesCooked failed: $e\n$st');
      return 0;
    }
  }

  /// Whether this recipe has ever been cooked. Same derived source as
  /// [timesCooked].
  Future<bool> hasBeenCooked(String recipeKey) async =>
      (await timesCooked(recipeKey)) > 0;

  Future<void> dispose() => _changes.close();
}
