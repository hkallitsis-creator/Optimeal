import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';

/// Local (on-device) persistence for two related Cook Mode features:
///
/// 1. **Active session recovery** — if the user leaves Cook Mode mid-cook
///    (back button, phone call, app backgrounded/killed), their progress
///    (active step, timer, completed steps, portions) survives until they
///    finish, or until 24 hours of inactivity pass, whichever comes first.
/// 2. **Recently Cooked** — a rolling memory of the last 3 recipes the user
///    actually opened in Cook Mode (not every "Try Another" variant).
///
/// Both are stored locally only (SharedPreferences), not in Supabase — this
/// is a lightweight, single-device safety net / convenience feature, not
/// permanent curated data (that's the separate future "Save if you liked
/// it" feature). Deliberately stores the full recipe payload (not just an
/// ID) so a future "promote to Saved" action can read straight from here.
class CookSessionStorageService {
  static const _activeSessionKey = 'cook_session_active_v1';
  static const _recentlyCookedKey = 'cook_session_recent_v1';
  static const _cookHistoryKey = 'cook_session_history_v1';
  static const _activeSessionMaxAge = Duration(hours: 24);
  static const _recentlyCookedMaxEntries = 3;
  static const _cookHistoryMaxEntries = 20;

  // ---- Active session -----------------------------------------------

  Future<void> saveActiveSession({
    required CookModeRecipePayload recipe,
    required bool cookStarted,
    required bool cookPaused,
    required int? activeStepIndex,
    required Set<int> completedSteps,
    required Duration activeRemaining,
    required int? currentPortions,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final json = {
      'recipe': _recipeToJson(recipe),
      'progress': {
        'cookStarted': cookStarted,
        'cookPaused': cookPaused,
        'activeStepIndex': activeStepIndex,
        'completedSteps': completedSteps.toList(),
        'activeRemainingSeconds': activeRemaining.inSeconds,
        'currentPortions': currentPortions,
      },
      'lastUpdatedAt': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_activeSessionKey, jsonEncode(json));
  }

  /// Returns the saved session, or null if there isn't one, it's malformed,
  /// or it's older than 24 hours (in which case it's also cleared).
  Future<ActiveCookSession?> loadActiveSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeSessionKey);
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final lastUpdatedAt = DateTime.parse(json['lastUpdatedAt'] as String);
      if (DateTime.now().difference(lastUpdatedAt) > _activeSessionMaxAge) {
        await clearActiveSession();
        return null;
      }

      final recipe = _recipeFromJson(json['recipe'] as Map<String, dynamic>);
      final progress = json['progress'] as Map<String, dynamic>;

      return ActiveCookSession(
        recipe: recipe,
        cookStarted: progress['cookStarted'] as bool? ?? false,
        cookPaused: progress['cookPaused'] as bool? ?? true,
        activeStepIndex: progress['activeStepIndex'] as int?,
        completedSteps: ((progress['completedSteps'] as List<dynamic>?) ?? const [])
            .map((e) => e as int)
            .toSet(),
        activeRemaining: Duration(seconds: progress['activeRemainingSeconds'] as int? ?? 0),
        currentPortions: progress['currentPortions'] as int?,
        lastUpdatedAt: lastUpdatedAt,
      );
    } catch (e) {
      // Malformed/stale data from an older app version — treat as absent
      // rather than crashing Cook Mode on launch.
      await clearActiveSession();
      return null;
    }
  }

  Future<void> clearActiveSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeSessionKey);
  }

  // ---- Recently Cooked -------------------------------------------------

  /// Adds [recipe] to the front of the Recently Cooked list. If a recipe
  /// with the same (trimmed, case-insensitive) title is already present,
  /// it's moved to the front instead of duplicated. List is capped at 3.
  Future<void> addRecentlyCooked(CookModeRecipePayload recipe) async {
    final prefs = await SharedPreferences.getInstance();
    // Best-effort: long-running history used for personalized suggestions.
    // This is deliberately separate from the 3-item Recently Cooked UI.
    await _appendToHistory(recipe, prefs: prefs);
    final existing = await loadRecentlyCooked();

    final normalizedTitle = recipe.title.trim().toLowerCase();
    final deduped =
        existing.where((e) => e.recipe.title.trim().toLowerCase() != normalizedTitle).toList();

    final updated = [
      RecentlyCookedEntry(recipe: recipe, cookedAt: DateTime.now()),
      ...deduped,
    ].take(_recentlyCookedMaxEntries).toList();

    final json = updated
        .map((e) => {
              'recipe': _recipeToJson(e.recipe),
              'cookedAt': e.cookedAt.toIso8601String(),
            })
        .toList();

    await prefs.setString(_recentlyCookedKey, jsonEncode(json));
  }

  Future<void> _appendToHistory(CookModeRecipePayload recipe, {SharedPreferences? prefs}) async {
    try {
      final effectivePrefs = prefs ?? await SharedPreferences.getInstance();
      final existing = await loadCookHistory(prefs: effectivePrefs);

      final normalizedTitle = recipe.title.trim().toLowerCase();
      final deduped = existing
          .where((e) => e.recipe.title.trim().toLowerCase() != normalizedTitle)
          .toList();

      final updated = [
        RecentlyCookedEntry(recipe: recipe, cookedAt: DateTime.now()),
        ...deduped,
      ].take(_cookHistoryMaxEntries).toList();

      final json = updated
          .map((e) => {
                'recipe': _recipeToJson(e.recipe),
                'cookedAt': e.cookedAt.toIso8601String(),
              })
          .toList();

      await effectivePrefs.setString(_cookHistoryKey, jsonEncode(json));
    } catch (e, st) {
      debugPrint('CookSessionStorageService: failed to append cook history: $e');
      debugPrint('$st');
    }
  }

  Future<List<RecentlyCookedEntry>> loadRecentlyCooked() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentlyCookedKey);
    if (raw == null) return const [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) {
            final m = e as Map<String, dynamic>;
            return RecentlyCookedEntry(
              recipe: _recipeFromJson(m['recipe'] as Map<String, dynamic>),
              cookedAt: DateTime.parse(m['cookedAt'] as String),
            );
          })
          .toList();
    } catch (e) {
      // Malformed data from an older app version — treat as empty rather
      // than crashing the Home screen.
      return const [];
    }
  }

  Future<List<RecentlyCookedEntry>> loadCookHistory({SharedPreferences? prefs}) async {
    final effectivePrefs = prefs ?? await SharedPreferences.getInstance();
    final raw = effectivePrefs.getString(_cookHistoryKey);
    if (raw == null) return const [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final decoded = <RecentlyCookedEntry>[];
      for (final e in list) {
        try {
          final m = e as Map<String, dynamic>;
          decoded.add(
            RecentlyCookedEntry(
              recipe: _recipeFromJson(m['recipe'] as Map<String, dynamic>),
              cookedAt: DateTime.parse(m['cookedAt'] as String),
            ),
          );
        } catch (_) {
          // Skip malformed entries rather than failing the whole history.
        }
      }

      // Sanitize/cap so older/bad data doesn't keep re-failing on future loads.
      final capped = decoded.take(_cookHistoryMaxEntries).toList();
      if (capped.length != decoded.length) {
        final json = capped
            .map((e) => {
                  'recipe': _recipeToJson(e.recipe),
                  'cookedAt': e.cookedAt.toIso8601String(),
                })
            .toList();
        await effectivePrefs.setString(_cookHistoryKey, jsonEncode(json));
      }

      return capped;
    } catch (e, st) {
      debugPrint('CookSessionStorageService: failed to load cook history: $e');
      debugPrint('$st');
      return const [];
    }
  }

  // ---- Shared recipe (de)serialization ----------------------------------

  static Map<String, dynamic> _recipeToJson(CookModeRecipePayload recipe) => {
        'title': recipe.title,
        'ingredients': recipe.ingredients,
        'steps': recipe.steps
            .map((s) => {
                  'title': s.title,
                  'heat': s.heat,
                  'durationMinutes': s.durationMinutes,
                  'bullets': s.bullets,
                })
            .toList(),
        'kitchenGear': recipe.kitchenGear,
        'description': recipe.description,
        'structuredIngredients':
            recipe.structuredIngredients?.map((i) => i.toJson()).toList(),
        'basePortions': recipe.basePortions,
        'curriculumLessonIds': recipe.curriculumLessonIds,
      };

  static CookModeRecipePayload _recipeFromJson(Map<String, dynamic> json) {
    return CookModeRecipePayload(
      title: json['title'] as String,
      ingredients:
          ((json['ingredients'] as List<dynamic>?) ?? const []).map((e) => e as String).toList(),
      steps: ((json['steps'] as List<dynamic>?) ?? const [])
          .map((e) {
            final m = e as Map<String, dynamic>;
            return CookModeStepPayload(
              title: m['title'] as String,
              heat: m['heat'] as String,
              durationMinutes: m['durationMinutes'] as int,
              bullets: ((m['bullets'] as List<dynamic>?) ?? const []).map((b) => b as String).toList(),
            );
          })
          .toList(),
      kitchenGear: (json['kitchenGear'] as List<dynamic>?)?.map((e) => e as String).toList(),
      description: json['description'] as String?,
      structuredIngredients: (json['structuredIngredients'] as List<dynamic>?)
          ?.map((e) => RecipeIngredient.fromJson(e as Map<String, dynamic>))
          .toList(),
      basePortions: json['basePortions'] as int?,
      curriculumLessonIds: _readStringList(json['curriculumLessonIds']),
    );
  }

  static List<String> _readStringList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final e in raw) {
      final s = e.toString().trim();
      if (s.isNotEmpty) out.add(s);
    }
    return out;
  }
}

/// A restored in-progress Cook Mode session, ready to resume.
class ActiveCookSession {
  const ActiveCookSession({
    required this.recipe,
    required this.cookStarted,
    required this.cookPaused,
    required this.activeStepIndex,
    required this.completedSteps,
    required this.activeRemaining,
    required this.currentPortions,
    required this.lastUpdatedAt,
  });

  final CookModeRecipePayload recipe;
  final bool cookStarted;
  final bool cookPaused;
  final int? activeStepIndex;
  final Set<int> completedSteps;
  final Duration activeRemaining;
  final int? currentPortions;
  final DateTime lastUpdatedAt;
}

/// One entry in the Recently Cooked list.
class RecentlyCookedEntry {
  const RecentlyCookedEntry({required this.recipe, required this.cookedAt});

  final CookModeRecipePayload recipe;
  final DateTime cookedAt;
}