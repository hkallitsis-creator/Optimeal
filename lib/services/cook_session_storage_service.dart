import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/data/diagram_keys.dart';
import 'package:optimeal/data/sensory_cue_vocabulary.dart';
import 'package:optimeal/models/planner_slot_ref.dart';
import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/models/recipe_origin.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/data_change_signal.dart';

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

  /// [RecentlyCookedEntry.source] value stamped on every history entry
  /// written from now on (device-test round F11). Marks that this entry's
  /// `recipe.curriculumLessonIds` came from the model's own declared
  /// `curriculum_lesson_id` field, not the older keyword-matching pipeline
  /// that populated the same field name before that migration. Entries
  /// written before this stamp existed decode with `source == null` —
  /// forward-only, nothing retroactively guessed or deleted; consumers
  /// that need to distinguish (ConfidenceClimbService, YourMonthCard) do
  /// so by filtering on this field themselves, not by adding logic here.
  static const String declaredKeySource = 'declared_key';

  // ---- Active session -----------------------------------------------

  Future<void> saveActiveSession({
    required CookModeRecipePayload recipe,
    required bool cookStarted,
    required bool cookPaused,
    required int? activeStepIndex,
    required Set<int> completedSteps,
    required Duration activeRemaining,
    required int? currentPortions,
    required CookModeSurface? surface,
    required bool isReCook,
    PlannerSlotRef? plannerSlot,
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
      'surface': surface?.name,
      'isReCook': isReCook,
      // Launch context, same category as `surface`: which Weekly Planner row
      // this cook was started from, so an interrupted planner cook still marks
      // the right slot when it is resumed. Absent on sessions saved before
      // CLAUDE.md roadmap item 27 — those resume with no slot and attribute
      // nothing, which is the safe reading.
      'plannerSlot': plannerSlot?.toJson(),
      'lastUpdatedAt': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_activeSessionKey, jsonEncode(json));
    AppDataChanges.cookLog.notify();
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

      // surface/isReCook are absent on sessions saved before CLAUDE.md
      // Roadmap item 28 — default to null/false (non-rescue-eligible)
      // rather than guessing an origin surface that was never recorded.
      final surfaceName = json['surface'] as String?;
      CookModeSurface? surface;
      if (surfaceName != null) {
        try {
          surface = CookModeSurface.values.byName(surfaceName);
        } catch (_) {
          surface = null;
        }
      }

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
        surface: surface,
        isReCook: json['isReCook'] as bool? ?? false,
        plannerSlot: PlannerSlotRef.fromJson(json['plannerSlot']),
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
    AppDataChanges.cookLog.notify();
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
      RecentlyCookedEntry(recipe: recipe, cookedAt: DateTime.now(), source: declaredKeySource),
      ...deduped,
    ].take(_recentlyCookedMaxEntries).toList();

    final json = updated
        .map((e) => {
              'recipe': _recipeToJson(e.recipe),
              'cookedAt': e.cookedAt.toIso8601String(),
              'source': e.source,
            })
        .toList();

    await prefs.setString(_recentlyCookedKey, jsonEncode(json));
    // One notify for both stores this method writes (history above, Recently
    // Cooked here) — readers re-read the whole local cook log anyway.
    AppDataChanges.cookLog.notify();
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
        RecentlyCookedEntry(recipe: recipe, cookedAt: DateTime.now(), source: declaredKeySource),
        ...deduped,
      ].take(_cookHistoryMaxEntries).toList();

      final json = updated
          .map((e) => {
                'recipe': _recipeToJson(e.recipe),
                'cookedAt': e.cookedAt.toIso8601String(),
                'source': e.source,
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
              source: m['source'] as String?,
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
              source: m['source'] as String?,
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
                  'source': e.source,
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
                  'ingredientsAdded': s.ingredientsAdded,
                  'sensoryCue': s.sensoryCue,
                  'techniqueDiagramId': s.techniqueDiagramId,
                })
            .toList(),
        'kitchenGear': recipe.kitchenGear,
        'description': recipe.description,
        'structuredIngredients':
            recipe.structuredIngredients?.map((i) => i.toJson()).toList(),
        'basePortions': recipe.basePortions,
        'curriculumLessonIds': recipe.curriculumLessonIds,
        // Provenance travels with the recipe (see RecipeOrigin), so a
        // resumed session and a re-cook both still know where the recipe
        // came from. Entries written before these keys existed decode to a
        // null origin, which correctly reads as "not rescue-eligible".
        'origin': recipe.origin?.name,
        'originEnteredIngredients': recipe.originEnteredIngredients,
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
              ingredientsAdded: (m['ingredientsAdded'] as List<dynamic>?)?.map((e) => e as String).toList(),
              sensoryCue: SensoryCueVocabulary.allKeys.contains(m['sensoryCue'])
                  ? m['sensoryCue'] as String
                  : SensoryCueVocabulary.noCueKey,
              techniqueDiagramId: allTechniqueDiagramKeys.contains(m['techniqueDiagramId'])
                  ? m['techniqueDiagramId'] as String
                  : noTechniqueDiagramKey,
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
      origin: RecipeOrigin.fromName(json['origin']),
      originEnteredIngredients: _readNullableStringList(json['originEnteredIngredients']),
    );
  }

  /// Like [_readStringList] but preserves the difference between "absent"
  /// and "present but empty" — [CookModeRecipePayload.originEnteredIngredients]
  /// is null when unknown, and that is not the same as an empty fridge.
  static List<String>? _readNullableStringList(dynamic raw) {
    if (raw is! List) return null;
    final out = _readStringList(raw);
    return out.isEmpty ? null : out;
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
    required this.surface,
    required this.isReCook,
    required this.lastUpdatedAt,
    this.plannerSlot,
  });

  final CookModeRecipePayload recipe;
  final bool cookStarted;
  final bool cookPaused;
  final int? activeStepIndex;
  final Set<int> completedSteps;
  final Duration activeRemaining;
  final int? currentPortions;

  /// The surface this session originally launched from, and whether it was
  /// a re-cook — carried through resume so a backgrounded-then-resumed
  /// session still logs (or doesn't log) exactly as it would have if
  /// finished without interruption. Null [surface] on sessions saved before
  /// CLAUDE.md Roadmap item 28 existed.
  final CookModeSurface? surface;
  final bool isReCook;

  /// The Weekly Planner slot this session was launched from, if any — carried
  /// through resume for the same reason [surface] is, so an interrupted
  /// planner cook still marks the row it belongs to. Null on sessions saved
  /// before CLAUDE.md roadmap item 27, and on every cook that did not start
  /// from a planner row.
  final PlannerSlotRef? plannerSlot;
  final DateTime lastUpdatedAt;
}

/// One entry in the Recently Cooked list or the longer-running cook
/// history list.
class RecentlyCookedEntry {
  const RecentlyCookedEntry({required this.recipe, required this.cookedAt, this.source});

  final CookModeRecipePayload recipe;
  final DateTime cookedAt;

  /// See [CookSessionStorageService.declaredKeySource]. Null for any entry
  /// written before that stamp existed.
  final String? source;
}