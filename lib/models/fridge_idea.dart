import 'dart:convert';

import 'package:flutter/foundation.dart';

/// One stage-1 Fridge Clearer idea: a **menu line, not a meal**.
///
/// Signed two-stage generation (2026-08-22): pressing "Let's cook" makes one
/// small call that returns three of these — a title, a total time, and which
/// of the user's ingredients the dish would clear. No steps, no quantities, no
/// full recipe. The full recipe is generated for exactly one idea, after the
/// user has chosen it.
///
/// Why the split is worth a second call: the old flow spent 7–10s generating a
/// complete recipe the user had not agreed to yet, and if they did not like it
/// their only move was "Try Another" — another 7–10s for another single guess.
/// Choosing among three summaries replaces retrying one recipe, which is why
/// the regenerate affordance is deliberately gone from this flow.
@immutable
class FridgeIdea {
  const FridgeIdea({
    required this.title,
    required this.totalTimeMinutes,
    required this.ingredientsCleared,
  });

  final String title;
  final int totalTimeMinutes;

  /// The ingredients the model says this dish uses, as the model named them.
  ///
  /// **Not authoritative on its own.** The user-facing clearance line is
  /// computed against the user's own entered list by
  /// [FridgeClearance.forIdea] — the model is asked which ingredients a dish
  /// uses, never asked to do the arithmetic in prose, because a model that
  /// writes "clears 3 of your 4" is one hallucinated digit away from lying
  /// about the whole point of the feature.
  final List<String> ingredientsCleared;

  @override
  bool operator ==(Object other) =>
      other is FridgeIdea &&
      other.title == title &&
      other.totalTimeMinutes == totalTimeMinutes &&
      listEquals(other.ingredientsCleared, ingredientsCleared);

  @override
  int get hashCode =>
      Object.hash(title, totalTimeMinutes, Object.hashAll(ingredientsCleared));

  @override
  String toString() =>
      'FridgeIdea($title, ${totalTimeMinutes}min, clears $ingredientsCleared)';
}

/// The computed clearance for one idea against what the user actually entered.
///
/// Every number here is derived app-side. [left] is **not** read from the
/// model's `ingredients_left` even though the schema asks for it: the two can
/// disagree, and when they do the user's own list is the one that matters.
/// Asking for it anyway is deliberate — it makes the model commit to a full
/// partition, which measurably improves how honestly it fills
/// `ingredients_cleared`.
@immutable
class FridgeClearance {
  const FridgeClearance({
    required this.entered,
    required this.cleared,
    required this.left,
  });

  /// What the user put in, in their own words and their own order.
  final List<String> entered;

  /// The subset of [entered] this idea uses.
  final List<String> cleared;

  /// The subset of [entered] this idea does not use.
  final List<String> left;

  int get clearedCount => cleared.length;
  int get enteredCount => entered.length;
  bool get clearsEverything => left.isEmpty && entered.isNotEmpty;

  /// Loose match between a user's word and the model's word.
  ///
  /// Case- and whitespace-insensitive, and containment either way so
  /// "Potatoes" matches "potato" and "Stale Bread" matches "bread". Anything
  /// cleverer (stemming, a synonym table) would be a guess about food language
  /// that could silently over-count clearance, which is the one number this
  /// screen must not inflate.
  static bool matches(String a, String b) {
    final x = a.trim().toLowerCase();
    final y = b.trim().toLowerCase();
    if (x.isEmpty || y.isEmpty) return false;
    return x == y || x.contains(y) || y.contains(x);
  }

  /// Partitions [entered] by whether [idea] uses it.
  ///
  /// Driven from the ENTERED list, not the model's: an ingredient the model
  /// invented and the user never had cannot count toward clearance, and this
  /// loop cannot count it because it never iterates the model's list.
  factory FridgeClearance.forIdea(FridgeIdea idea, List<String> entered) {
    final cleared = <String>[];
    final left = <String>[];
    for (final item in entered) {
      final used =
          idea.ingredientsCleared.any((claimed) => matches(item, claimed));
      (used ? cleared : left).add(item);
    }
    return FridgeClearance(entered: entered, cleared: cleared, left: left);
  }
}

/// Parses the stage-1 reply into at most three ideas.
///
/// Tolerant about **shape**, strict about **substance**:
/// - accepts `{"ideas": [...]}` and a bare `[...]`;
/// - accepts 1–3 ideas rather than demanding exactly 3, because two real
///   choices beat an error screen;
/// - skips any entry with no usable title;
/// - returns **null** when nothing usable came back.
///
/// **Null means the screen shows its error card with a retry — it never
/// fabricates ideas.** That is the opposite of what this screen used to do
/// when full-recipe parsing failed (CLAUDE.md roadmap item 20: it invented a
/// hardcoded fallback recipe), and it is deliberate. A made-up menu is worse
/// than a visible failure, and a fabricated idea would go on to anchor a real
/// stage-2 generation.
List<FridgeIdea>? parseFridgeIdeasJson(String raw) {
  try {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final decoded = jsonDecode(trimmed);
    final List<dynamic> list;
    if (decoded is Map && decoded['ideas'] is List) {
      list = decoded['ideas'] as List<dynamic>;
    } else if (decoded is List) {
      list = decoded;
    } else {
      debugPrint('parseFridgeIdeasJson: no "ideas" array in reply');
      return null;
    }

    final ideas = <FridgeIdea>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      final title = (entry['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;

      final minutes = int.tryParse(
              '${entry['total_time_minutes'] ?? entry['totalTimeMinutes'] ?? ''}'
                  .trim()) ??
          0;

      final clearedRaw =
          entry['ingredients_cleared'] ?? entry['ingredientsCleared'];
      final cleared = clearedRaw is List
          ? clearedRaw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList(growable: false)
          : const <String>[];

      ideas.add(FridgeIdea(
        title: title,
        totalTimeMinutes: minutes,
        ingredientsCleared: cleared,
      ));
      if (ideas.length == 3) break;
    }

    if (ideas.isEmpty) {
      debugPrint('parseFridgeIdeasJson: reply had no usable ideas');
      return null;
    }
    return ideas;
  } catch (e) {
    debugPrint('parseFridgeIdeasJson: failed to decode stage-1 reply: $e');
    return null;
  }
}
