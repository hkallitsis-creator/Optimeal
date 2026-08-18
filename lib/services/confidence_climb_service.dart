import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/models/user_profile.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/widgets/curriculum_drawer_content.dart';

/// Result of evaluating Confidence Climb after a cook session completes.
class ConfidenceClimbEvaluation {
  const ConfidenceClimbEvaluation({
    this.celebrationLine,
    this.tierUpTarget,
    this.repeatTechniqueIds = const <String>{},
    this.comfortableTechniqueIds = const <String>{},
  });

  /// An occasional, non-blocking line for the existing post-cook
  /// celebration flow (e.g. "3rd time this month using Braising — you're
  /// building real knife + heat control."). Null most of the time — this
  /// is deliberately rare, not shown on every cook.
  final String? celebrationLine;

  /// Non-null exactly when the user has crossed the rep threshold for a
  /// tier they haven't already been offered — the caller should show the
  /// one-time "Move up to X?" prompt for this tier.
  final KitchenConfidence? tierUpTarget;

  /// Subset of the just-cooked technique ids the user has completed before
  /// (docs/decisions_2026-08-17.md item 7) — What You Learned appends the
  /// "Are you comfortable with this technique?" question for these, and
  /// only these. Empty on a technique's first-ever completion.
  final Set<String> repeatTechniqueIds;

  /// Subset of the just-cooked technique ids already marked comfortable —
  /// the caller should exclude these from What You Learned entirely (see
  /// [ConfidenceClimbService.loadComfortableTechniqueIds]).
  final Set<String> comfortableTechniqueIds;
}

/// Confidence Climb: turns technique reps already tracked via
/// [CookSessionStorageService]'s cook history (tagged with the same
/// `curriculumLessonIds` the "What You Learned" pipeline already produces
/// via `ChefService.matchedCurriculumDrawerKeys` — no new matching logic
/// here) into an occasional celebration line and a one-time kitchen-
/// confidence tier-up offer.
///
/// See CLAUDE.md Retention Features Backlog item 2.
class ConfidenceClimbService {
  static const _promptedPrefsKeyPrefix = 'confidence_climb_prompted_v1_';

  /// Technique ids the user has told Confidence Climb they're comfortable
  /// with (docs/decisions_2026-08-17.md item 7) — What You Learned's
  /// confidence question stops appearing for these, and the sheet itself
  /// stops surfacing on a cook whose only technique(s) are all comfortable.
  /// Reversible from Confidence Climb (see [markNotComfortable]) — comfort
  /// is expected to regress, not just grow.
  static const _comfortableTechniquesPrefsKey = 'confidence_climb_comfortable_techniques_v1';

  /// Reps of technique-tagged cooking required before offering a tier-up.
  /// Deliberately counts ANY tagged technique rep (not one specific
  /// technique) — the point is broad kitchen mileage, not mastery of a
  /// single move.
  static const int _tierUpRepThreshold = 5;

  /// Reps of the SAME technique within the current calendar month before
  /// the post-cook celebration line mentions it.
  static const int _celebrationRepThreshold = 3;

  final CookSessionStorageService _sessionStorage;

  ConfidenceClimbService({CookSessionStorageService? sessionStorage}) : _sessionStorage = sessionStorage ?? CookSessionStorageService();

  static KitchenConfidence? _nextTier(KitchenConfidence current) {
    switch (current) {
      case KitchenConfidence.beginner:
        return KitchenConfidence.fastEfficient;
      case KitchenConfidence.fastEfficient:
        return KitchenConfidence.confident;
      case KitchenConfidence.confident:
        return null;
    }
  }

  static String tierDisplayName(KitchenConfidence tier) {
    switch (tier) {
      case KitchenConfidence.beginner:
        return 'Beginner';
      case KitchenConfidence.fastEfficient:
        return 'Fast & Efficient';
      case KitchenConfidence.confident:
        return 'Confident Cook';
    }
  }

  String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }

  /// Call right after a cook session completes, with the technique ids for
  /// the just-finished recipe (its `curriculumLessonIds`, already tagged
  /// on [RecentlyCookedEntry.recipe] via the shared matching pipeline).
  /// Fails open (returns an empty evaluation) — this is a nice-to-have,
  /// never something that should block or crash the post-cook flow.
  Future<ConfidenceClimbEvaluation> evaluate({
    required List<String> justCookedTechniqueIds,
    required KitchenConfidence currentConfidence,
  }) async {
    try {
      if (justCookedTechniqueIds.isEmpty) return const ConfidenceClimbEvaluation();

      // Forward-only filter (device-test round F11): only entries stamped
      // as declared-key source are aggregated, so pre-migration
      // keyword-matched entries (which used the same curriculumLessonIds
      // field name under the old matching pipeline) can't mix into the
      // same count. Nothing is deleted or retroactively guessed — an
      // unstamped entry is simply excluded from this aggregation.
      final allHistory = await _sessionStorage.loadCookHistory();
      final history = allHistory
          .where((e) => e.source == CookSessionStorageService.declaredKeySource)
          .toList(growable: false);
      final now = DateTime.now();

      // --- Celebration line: same-technique reps within this calendar month.
      String? celebrationLine;
      var bestCount = 0;
      for (final techniqueId in justCookedTechniqueIds) {
        final count = history.where((e) {
          if (e.cookedAt.year != now.year || e.cookedAt.month != now.month) return false;
          return (e.recipe.curriculumLessonIds ?? const []).contains(techniqueId);
        }).length;
        if (count > bestCount) {
          bestCount = count;
          if (count >= _celebrationRepThreshold) {
            final title = resolveDrawerEntry(techniqueId)?.title;
            if (title != null) {
              celebrationLine = "${_ordinal(count)} time this month using $title — you're building real knife + heat control.";
            }
          }
        }
      }

      // --- Confidence question eligibility (docs/decisions_2026-08-17.md
      // item 7): a technique is a "repeat" if it appears more than once in
      // history — the just-finished cook's own entry is already recorded
      // there (CookSessionStorageService.addRecentlyCooked is called when
      // Cook Mode opens, not when it completes), so count > 1 means at
      // least one PRIOR completion exists, not just this one. All-time,
      // not month-scoped, unlike the celebration line above.
      final repeatTechniqueIds = <String>{};
      for (final techniqueId in justCookedTechniqueIds) {
        final count = history.where((e) => (e.recipe.curriculumLessonIds ?? const []).contains(techniqueId)).length;
        if (count > 1) repeatTechniqueIds.add(techniqueId);
      }
      final comfortableTechniqueIds = await loadComfortableTechniqueIds();
      final comfortableAmongJustCooked = justCookedTechniqueIds.toSet().intersection(comfortableTechniqueIds);

      // --- Tier-up: total reps of ANY tagged technique, all-time (within
      // the 20-entry rolling history), gated so it's offered at most once
      // per tier transition.
      final target = _nextTier(currentConfidence);
      KitchenConfidence? tierUpTarget;
      if (target != null) {
        final taggedReps = history.where((e) => (e.recipe.curriculumLessonIds ?? const []).isNotEmpty).length;
        if (taggedReps >= _tierUpRepThreshold && !(await _alreadyPrompted(currentConfidence))) {
          tierUpTarget = target;
        }
      }

      return ConfidenceClimbEvaluation(
        celebrationLine: celebrationLine,
        tierUpTarget: tierUpTarget,
        repeatTechniqueIds: repeatTechniqueIds,
        comfortableTechniqueIds: comfortableAmongJustCooked,
      );
    } catch (e) {
      debugPrint('ConfidenceClimbService.evaluate failed (continuing): $e');
      return const ConfidenceClimbEvaluation();
    }
  }

  /// All technique ids currently marked comfortable. Fails open (empty set)
  /// — a read failure here should suppress nothing, never crash Cook Mode.
  Future<Set<String>> loadComfortableTechniqueIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_comfortableTechniquesPrefsKey) ?? const []).toSet();
    } catch (e) {
      debugPrint('ConfidenceClimbService.loadComfortableTechniqueIds failed: $e');
      return const {};
    }
  }

  Future<void> markComfortable(String techniqueId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = (prefs.getStringList(_comfortableTechniquesPrefsKey) ?? const []).toSet();
    current.add(techniqueId);
    await prefs.setStringList(_comfortableTechniquesPrefsKey, current.toList());
  }

  /// Reverses [markComfortable] — confidence regresses, and Confidence
  /// Climb is meant to let a user say so (docs/decisions_2026-08-17.md
  /// item 7 / CLAUDE.md Package E3).
  Future<void> markNotComfortable(String techniqueId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = (prefs.getStringList(_comfortableTechniquesPrefsKey) ?? const []).toSet();
    current.remove(techniqueId);
    await prefs.setStringList(_comfortableTechniquesPrefsKey, current.toList());
  }

  Future<bool> _alreadyPrompted(KitchenConfidence fromTier) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_promptedPrefsKeyPrefix${fromTier.name}') ?? false;
  }

  /// Marks the tier-up prompt as shown for [fromTier] so it's never offered
  /// again for that transition, whether the user accepted or dismissed it.
  Future<void> markPrompted(KitchenConfidence fromTier) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_promptedPrefsKeyPrefix${fromTier.name}', true);
  }
}
