/// Compatibility validator over the signed cooking-times table.
///
/// Implements rules 1–4 and 6 of section 7 of `docs/cooking_times_table.md`
/// ("How the validator uses this", printed on page 6, unmodified):
///
///  1. Read each step's `ingredients_added` and the cut declared for each.
///  2. Resolve every ingredient to a band via the table and size scaling.
///  3. Within a single step, compare bands. More than one band apart is a flag.
///  4. Compare each ingredient's band against the step's stated duration.
///     Materially longer is a flag.
///  6. On flag, inject a correction and regenerate rather than blocking.
///
/// **Rule 5 is deliberately NOT here.** "Any poultry or pork step without a
/// verification instruction is a flag" is a food-safety rule, and food safety
/// is roadmap item 1 (the safety validator), which is a separate pre-launch
/// build with its own signed hazard registry. This file is about timing only.
/// `SensoryCue.mandatoryOnPoultryAndPork` already exists for that build.
///
/// **Grouping is per step, not per parallel run.** The paper says "within a
/// single step" and the recipe schema carries no parallelism marker; rather
/// than invent a new declared field to express "meanwhile", this reads exactly
/// what rule 3 asks for. Concurrent steps are usually a second pan anyway,
/// which is not co-cooking.
///
/// Everything about this validator fails open. An unknown key, an absent key,
/// a pending row, an unmatched ingredient name and a step with fewer than two
/// resolvable ingredients all produce no flag — never a false positive, never
/// a block, and never a user-visible warning.
library;

import 'package:flutter/foundation.dart';

import 'package:optimeal/data/cooking_times.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';

/// Why a step was flagged.
enum CompatibilityFlagKind {
  /// Two ingredients in one step are more than one band apart (rule 3).
  bandSpread,

  /// The step's stated duration is more than one band below what an
  /// ingredient in it needs (rule 4).
  durationTooShort,
}

/// One machine-readable finding. Kept flat and primitive so it serialises
/// straight into a log line without a codec.
@immutable
class CompatibilityFlag {
  const CompatibilityFlag({
    required this.kind,
    required this.stepIndex,
    required this.stepTitle,
    required this.slowKey,
    required this.slowBand,
    required this.bandDelta,
    this.fastKey,
    this.fastBand,
    this.stepMinutes,
  });

  final CompatibilityFlagKind kind;

  /// Zero-based index into the recipe's step list.
  final int stepIndex;
  final String stepTitle;

  /// The declared key of the slower ingredient — the one that governs.
  final String slowKey;
  final CookBand slowBand;

  /// The faster ingredient of the pair. Null on a [durationTooShort] flag,
  /// where the comparison is against a duration rather than an ingredient.
  final String? fastKey;
  final CookBand? fastBand;

  /// Total heated minutes this ingredient gets, from the step that adds it to
  /// the end of the recipe. On a [durationTooShort] flag only.
  final int? stepMinutes;

  /// How many bands apart the two sides are. Always >= 2 on a real flag —
  /// the signed tolerance is one band.
  final int bandDelta;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'step_index': stepIndex,
        'step_title': stepTitle,
        'slow_key': slowKey,
        'slow_band': slowBand.label,
        if (fastKey != null) 'fast_key': fastKey,
        if (fastBand != null) 'fast_band': fastBand!.label,
        if (stepMinutes != null) 'step_minutes': stepMinutes,
        'band_delta': bandDelta,
      };

  /// The sentence handed back to the model on a correction retry. Names the
  /// offending pair and the two remedies the paper itself gives ("requires a
  /// staggered add, or a different cut size to bring them closer").
  String get correctionSentence {
    switch (kind) {
      case CompatibilityFlagKind.bandSpread:
        return 'Step ${stepIndex + 1} ("$stepTitle") adds $slowKey (${slowBand.label}, '
            '${_bandRange(slowBand)}) and $fastKey (${fastBand!.label}, '
            '${_bandRange(fastBand!)}) at the same time. That is $bandDelta bands apart; '
            'the limit is one. Give the slower one a head start in its own earlier step, '
            'or cut it smaller so the two land within one band of each other.';
      case CompatibilityFlagKind.durationTooShort:
        return '$slowKey enters at step ${stepIndex + 1} ("$stepTitle") and then gets '
            'only $stepMinutes minutes of heat before the recipe ends, but it needs '
            '${slowBand.label} (${_bandRange(slowBand)}). Either give it a realistic '
            'cooking time or cut it smaller.';
    }
  }

  @override
  String toString() => correctionSentence;
}

String _bandRange(CookBand b) =>
    b.maxMinutes == null ? '${b.minMinutes}+ min' : '${b.minMinutes}-${b.maxMinutes} min';

/// The outcome of one validation pass.
@immutable
class CompatibilityReport {
  const CompatibilityReport({
    required this.flags,
    required this.stepsChecked,
    required this.ingredientsResolved,
    required this.ingredientsSkipped,
    required this.unknownKeys,
  });

  const CompatibilityReport.clean()
      : flags = const [],
        stepsChecked = 0,
        ingredientsResolved = 0,
        ingredientsSkipped = 0,
        unknownKeys = const [];

  final List<CompatibilityFlag> flags;

  /// Steps that had at least one resolvable ingredient.
  final int stepsChecked;

  /// Ingredient mentions that resolved to at least one band.
  final int ingredientsResolved;

  /// Ingredient mentions that could not be checked — no declared key, a key
  /// outside the closed list, or a row whose timing is pending (red lentils).
  final int ingredientsSkipped;

  /// Keys the model declared that are not in the closed list. Logged so the
  /// real-world rejection rate is visible rather than guessed at.
  final List<String> unknownKeys;

  bool get isClean => flags.isEmpty;

  /// The correction note appended to a retry prompt. Names every violating
  /// pair rather than only the first, so one retry can fix a recipe with two
  /// bad steps instead of burning both retries one flag at a time.
  String buildCorrectionNote() {
    if (flags.isEmpty) return '';
    final buffer = StringBuffer(
      'CORRECTION REQUIRED. Your previous version breaks the cooking-time '
      'compatibility rule: ingredients that go into the pan together must be '
      'within one time band of each other. Fix these and return the whole '
      'recipe again in the same JSON shape:\n',
    );
    for (final f in flags) {
      buffer.writeln('- ${f.correctionSentence}');
    }
    return buffer.toString().trimRight();
  }

  Map<String, dynamic> toJson() => {
        'flags': flags.map((f) => f.toJson()).toList(),
        'steps_checked': stepsChecked,
        'ingredients_resolved': ingredientsResolved,
        'ingredients_skipped': ingredientsSkipped,
        if (unknownKeys.isNotEmpty) 'unknown_keys': unknownKeys,
      };
}

/// Runs the compatibility check over a parsed recipe.
///
/// [unknownKeys] carries what the parser already rejected on the way in, so
/// the report can log the model's real-world miss rate against the closed list
/// rather than leaving it to be guessed at.
CompatibilityReport validateCookingCompatibility(
  CookModeRecipePayload recipe, {
  List<String> unknownKeys = const [],
}) {
  final structured = recipe.structuredIngredients;
  if (structured == null || structured.isEmpty) {
    return CompatibilityReport(
      flags: const [],
      stepsChecked: 0,
      ingredientsResolved: 0,
      ingredientsSkipped: 0,
      unknownKeys: unknownKeys,
    );
  }

  // Ingredient name to declared key. Names are the join between a step's
  // `ingredients_added` and the top-level ingredient list, exactly as rule 1
  // describes; matching is case- and whitespace-insensitive because the model
  // does not reliably repeat its own casing.
  final keyByName = <String, String>{};
  for (final ing in structured) {
    final key = ing.cookingTimesKey;
    if (key != null) keyByName[_normalise(ing.name)] = key;
  }

  // Cook time still to come from each step onward, counting heated steps only.
  // Rule 4 needs this rather than a single step's stated duration: an
  // ingredient added in step 1 keeps cooking through steps 2..n, so comparing
  // its band against step 1 alone is simply the wrong arithmetic. Measured on
  // real dev output, that was the single largest source of false flags —
  // stewing beef browned for 10 minutes and then simmered for 90 was being
  // flagged as a 10-minute step.
  final cookMinutesFrom = List<int>.filled(recipe.steps.length + 1, 0);
  for (var i = recipe.steps.length - 1; i >= 0; i--) {
    final s = recipe.steps[i];
    cookMinutesFrom[i] =
        cookMinutesFrom[i + 1] + (_isOffHeat(s) ? 0 : s.durationMinutes);
  }

  final flags = <CompatibilityFlag>[];
  final durationCheckedKeys = <String>{};
  var stepsChecked = 0;
  var resolved = 0;
  var skipped = 0;

  for (var i = 0; i < recipe.steps.length; i++) {
    final step = recipe.steps[i];
    final added = step.ingredientsAdded;
    if (added == null || added.isEmpty) continue;

    // An off-heat step is chopping, seasoning, assembling or resting. Nothing
    // is cooking, so nothing can be co-cooking, and the compatibility rule has
    // nothing to say about it. Real dev output puts four ingredients into a
    // single "Prepare Ingredients" step routinely; treating that as a pan is
    // a false flag every time.
    if (_isOffHeat(step)) continue;

    // Distinct keys only: the same ingredient named twice in one step is one
    // thing in the pan, and comparing it with itself is always a pass anyway.
    final keysInStep = <String>[];
    for (final name in added) {
      final key = _lookup(keyByName, name);
      if (key == null || CookingTimes.resolveBands(key).isEmpty) {
        skipped++;
        continue;
      }
      resolved++;
      if (!keysInStep.contains(key)) keysInStep.add(key);
    }
    if (keysInStep.isEmpty) continue;
    stepsChecked++;

    // Rule 3 — pairwise within the step.
    for (var a = 0; a < keysInStep.length; a++) {
      for (var b = a + 1; b < keysInStep.length; b++) {
        final flag = _comparePair(keysInStep[a], keysInStep[b], i, step.title);
        if (flag != null) flags.add(flag);
      }
    }

    // Rule 4 — each ingredient against the cook time it actually gets, which
    // runs from the step that first adds it to the end of the recipe. Checked
    // once per ingredient, at that first step.
    for (final key in keysInStep) {
      if (!durationCheckedKeys.add(key)) continue;
      final flag = _compareDuration(key, cookMinutesFrom[i], i, step.title);
      if (flag != null) flags.add(flag);
    }
  }

  return CompatibilityReport(
    flags: List.unmodifiable(flags),
    stepsChecked: stepsChecked,
    ingredientsResolved: resolved,
    ingredientsSkipped: skipped,
    unknownKeys: unknownKeys,
  );
}

/// Compares two declared keys. A dual-band row (lamb, which is B3 pan-fried
/// and B6 braised) passes if ANY of its bands is compatible — the recipe's
/// intent decides which regime it is in, and the paper does not resolve that
/// row, so the permissive reading is the fail-open one.
CompatibilityFlag? _comparePair(String keyA, String keyB, int stepIndex, String stepTitle) {
  final bandsA = CookingTimes.resolveBands(keyA);
  final bandsB = CookingTimes.resolveBands(keyB);
  if (bandsA.isEmpty || bandsB.isEmpty) return null;

  var worst = 0;
  CookBand? worstA, worstB;
  for (final a in bandsA) {
    for (final b in bandsB) {
      final d = a.distanceTo(b);
      if (d <= 1) return null; // some pairing is compatible — no flag
      if (d > worst) {
        worst = d;
        worstA = a;
        worstB = b;
      }
    }
  }
  if (worst <= 1) return null;

  final aIsSlower = worstA!.index > worstB!.index;
  return CompatibilityFlag(
    kind: CompatibilityFlagKind.bandSpread,
    stepIndex: stepIndex,
    stepTitle: stepTitle,
    slowKey: aIsSlower ? keyA : keyB,
    slowBand: aIsSlower ? worstA : worstB,
    fastKey: aIsSlower ? keyB : keyA,
    fastBand: aIsSlower ? worstB : worstA,
    bandDelta: worst,
  );
}

/// Rule 4. [stepMinutes] is the total heated time the ingredient gets from
/// [stepIndex] to the end of the recipe, not one step's duration. Uses the
/// same one-band tolerance rather than inventing a second threshold: landing
/// two or more bands short is "materially longer" in the paper's sense.
///
/// Skipped entirely for the three package-instruction rows — Harris's ruling
/// is that their band stands but their minutes carry no authority, so a
/// duration disagreement on those rows is not evidence of anything.
CompatibilityFlag? _compareDuration(String key, int stepMinutes, int stepIndex, String stepTitle) {
  if (stepMinutes <= 0) return null;
  if (CookingTimes.hasAdvisoryMinutes(key)) return null;

  final bands = CookingTimes.resolveBands(key);
  if (bands.isEmpty) return null;

  final stated = bandForMinutes(stepMinutes);
  // Permissive on dual-band rows, same reasoning as _comparePair.
  final closest = bands.map((b) => b.index - stated.index).reduce((a, b) => a < b ? a : b);
  if (closest <= 1) return null;

  final band = bands.firstWhere((b) => b.index - stated.index == closest);
  return CompatibilityFlag(
    kind: CompatibilityFlagKind.durationTooShort,
    stepIndex: stepIndex,
    stepTitle: stepTitle,
    slowKey: key,
    slowBand: band,
    stepMinutes: stepMinutes,
    bandDelta: closest,
  );
}

/// A step with no heat under it. The schema's closed heat vocabulary is
/// `low|medium|medium_high|off_heat`; anything unrecognised is treated as
/// heated, so a model that invents a heat value gets checked rather than
/// silently skipped.
bool _isOffHeat(CookModeStepPayload step) => step.heat.trim() == 'off_heat';

String _normalise(String s) => s.trim().toLowerCase();

/// Exact match first, then a containment fallback in both directions — the
/// model writes "chicken breast" in the ingredient list and "diced chicken
/// breast" in `ingredients_added` often enough to be worth handling, and a
/// wrong match here can only ever cost a spurious skip, never a wrong band.
String? _lookup(Map<String, String> keyByName, String rawName) {
  final name = _normalise(rawName);
  if (name.isEmpty) return null;
  final exact = keyByName[name];
  if (exact != null) return exact;
  for (final entry in keyByName.entries) {
    if (name.contains(entry.key) || entry.key.contains(name)) return entry.value;
  }
  return null;
}
