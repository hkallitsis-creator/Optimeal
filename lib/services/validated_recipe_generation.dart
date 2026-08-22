import 'package:flutter/foundation.dart';

import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/allergen_flag_log.dart';
import 'package:optimeal/services/allergen_guard.dart';
import 'package:optimeal/services/compatibility_flag_log.dart';
import 'package:optimeal/services/cooking_compatibility_validator.dart';
import 'package:optimeal/services/safety_flag_log.dart';
import 'package:optimeal/services/safety_validator.dart';

/// Why a generation attempt is being made. Carried into the attempt so the
/// caller can bill each call to its own cost surface — a compatibility retry
/// and a safety retry are different work and must not land in the same bucket
/// in `api_call_cost_log`.
enum RecipeRetryKind {
  /// The first attempt.
  first,

  /// A regeneration prompted by the cooking-times compatibility validator.
  compatibility,

  /// A regeneration prompted by the safety validator.
  safety,

  /// A regeneration prompted by the allergen guard.
  allergen,
}

/// One generation attempt. [correctionNote] is null on the first attempt and
/// carries a validator's correction text on a retry; [retryKind] lets the
/// caller bill the call to the right cost surface.
typedef RecipeGenerationAttempt = Future<String?> Function({
  String? correctionNote,
  required RecipeRetryKind retryKind,
});

/// Parses one raw model reply. [unknownKeysSink] is handed to
/// `parseChefRecipeJson` so declared keys outside the closed list are counted.
typedef RecipeAttemptParser = Future<CookModeRecipePayload?> Function(
  String raw,
  List<String> unknownKeysSink,
);

/// What the caller gets back. [recipe] is null only when generation itself
/// failed — an invalid or flagged recipe is still served.
@immutable
class ValidatedRecipeResult {
  const ValidatedRecipeResult({
    required this.recipe,
    required this.report,
    required this.retriesUsed,
    required this.servedWithFlags,
    this.safetyReport = const SafetyReport.clean(),
    this.safetyRetriesUsed = 0,
    this.servedWithSafetyFindings = false,
    this.allergenViolations = const [],
    this.allergenRetriesUsed = 0,
  });

  final CookModeRecipePayload? recipe;
  final CompatibilityReport report;

  /// How many compatibility corrections were spent, 0 to
  /// [kMaxCompatibilityRetries].
  final int retriesUsed;

  /// True when the recipe handed back still breaks the one-band rule — the
  /// silent fail-open case. **Nothing in the UI reads this**; it exists for
  /// the log and for tests.
  final bool servedWithFlags;

  /// The safety pass over the recipe that is actually being served, including
  /// the deterministic injections that were applied to it.
  final SafetyReport safetyReport;

  /// How many safety corrections were spent, 0 to [kMaxSafetyRetries].
  final int safetyRetriesUsed;

  /// True when a correctable safety finding survived every correction round.
  /// The recipe is still served — that is the registry's signed behaviour —
  /// but H1's injected cue has been applied regardless.
  final bool servedWithSafetyFindings;

  /// Allergen violations still present on the served recipe. **Empty is the
  /// only acceptable steady state**; a non-empty list means the guard failed
  /// open and the caller is serving a recipe containing something the user
  /// told us they cannot eat.
  final List<AllergenViolation> allergenViolations;

  final int allergenRetriesUsed;
}

/// Signed cap. Two corrections, then serve whatever we have.
const int kMaxCompatibilityRetries = 2;

/// Allergen corrections, same cap as the other two layers.
const int kMaxAllergenRetries = 2;

/// Generate → the full chain (compat → safety → allergen) → deterministic H1
/// injection last → serve.
///
/// # Every regenerate re-enters the chain from the top
///
/// Any regeneration — a compatibility correction, a safety correction, an
/// allergen correction — produces a **whole new recipe**, and a new recipe is
/// judged by every validator, not only the one that asked for it. Before the
/// 2026-08-23 insurance bundle the three layers ran as sequential
/// settle-completely loops, so an allergen retry's output re-entered nothing:
/// a new H2 violation on it was re-detected for the log and then served with
/// no correction round (audit M-4). Now an accepted regenerate loops back to
/// the top of the chain, and each layer corrects what it finds for as long as
/// its own budget lasts.
///
/// Retry budgets stay **per-validator** ([kMaxCompatibilityRetries] /
/// [kMaxSafetyRetries] / [kMaxAllergenRetries], 2 each) and a regenerate
/// triggered by one validator does not refund the others — so the worst case
/// is unchanged: 1 + 2 + 2 + 2 = **7 model calls per recipe**. Priority when
/// several layers have findings at once is unchanged too: compat first,
/// safety second, allergen last-word — the layer whose failure is an allergic
/// reaction corrects nearest to serving, so nothing can re-break a correction
/// it won.
///
/// The deterministic injection is applied **last of all**, after every
/// correction round of every layer, so nothing downstream can undo it. That
/// is the concrete meaning of "injection must survive any retry".
///
/// # Two different philosophies in one function
///
/// The compatibility half is advisory and fails open silently
/// (`CookingCompatibilityValidator`'s own doc explains why). The safety half
/// does not fail open on H1: the cue is written onto the recipe by the app
/// whether or not the model ever cooperated, and no failure path skips it.
/// The remaining safety rules follow the registry's signed
/// correction-and-regenerate behaviour, capped at [kMaxSafetyRetries], after
/// which the recipe is served and the finding logged — a signed decision,
/// recorded in `docs/safety_hazard_registry.md`, not a relaxation invented
/// here.
///
/// A retry that fails to generate, fails to parse, or comes back worse does
/// NOT discard the recipe we already have, in any layer — it only spends
/// that layer's budget. Losing a servable recipe to a failed correction
/// attempt would be strictly worse than serving the flagged one, which is
/// the same reasoning the caps themselves rest on.
Future<ValidatedRecipeResult> generateValidatedRecipe({
  required RecipeGenerationAttempt attempt,
  required RecipeAttemptParser parse,
  required String logSurface,
  int maxRetries = kMaxCompatibilityRetries,
  int maxSafetyRetries = kMaxSafetyRetries,
  int maxAllergenRetries = kMaxAllergenRetries,
  List<String> avoidedAllergens = const [],
}) async {
  // ── First generation. A failure here is the caller's existing error path.
  final firstRaw = await attempt(
    correctionNote: null,
    retryKind: RecipeRetryKind.first,
  );
  if (firstRaw == null || firstRaw.trim().isEmpty) {
    return const ValidatedRecipeResult(
      recipe: null,
      report: CompatibilityReport.clean(),
      retriesUsed: 0,
      servedWithFlags: false,
    );
  }
  var unknownKeys = <String>[];
  var best = await parse(firstRaw, unknownKeys);
  if (best == null) {
    return const ValidatedRecipeResult(
      recipe: null,
      report: CompatibilityReport.clean(),
      retriesUsed: 0,
      servedWithFlags: false,
    );
  }

  var retriesUsed = 0;
  var safetyRetriesUsed = 0;
  var allergenRetriesUsed = 0;
  var bestReport = validateCookingCompatibility(best, unknownKeys: unknownKeys);
  var safetyReport = validateRecipeSafety(best);
  var violations =
      findAllergenViolations(recipe: best, avoided: avoidedAllergens);

  // A correction round that fails outright (no reply, or unparseable) closes
  // its layer for this generation — same as the pre-re-entry loops, where a
  // failed retry broke the layer's loop: after a hard failure, immediately
  // firing the layer's remaining budget at the same model is more likely to
  // burn a billed call than to help. A round that parses but comes back
  // WORSE only spends the budget point; the layer may try again.
  var compatClosed = false;
  var safetyClosed = false;
  var allergenClosed = false;

  /// One correction round for whichever layer speaks first. Returns true when
  /// a candidate was ACCEPTED (strictly better on the asking layer's own
  /// measure) — the caller then re-enters the chain from the top.
  Future<bool> correctionRound({
    required String note,
    required RecipeRetryKind kind,
    required void Function() close,
    required bool Function(
            CookModeRecipePayload candidate, List<String> candidateKeys)
        accept,
  }) async {
    final raw = await attempt(correctionNote: note, retryKind: kind);
    if (raw == null || raw.trim().isEmpty) {
      close();
      return false;
    }
    final candidateKeys = <String>[];
    final parsed = await parse(raw, candidateKeys);
    if (parsed == null) {
      close();
      return false;
    }
    if (!accept(parsed, candidateKeys)) return false;
    best = parsed;
    unknownKeys = candidateKeys;
    return true;
  }

  // ── The chain. Every iteration below either breaks (nothing correctable,
  // or every relevant budget spent) or has consumed exactly one budget
  // point, so it terminates in at most 2+2+2 correction rounds. A `continue`
  // after an accepted candidate is the re-entry: the new recipe faces every
  // layer again, top first.
  while (true) {
    // 1 — compatibility (advisory, silent fail-open).
    bestReport = validateCookingCompatibility(best!, unknownKeys: unknownKeys);
    if (!bestReport.isClean && retriesUsed < maxRetries && !compatClosed) {
      retriesUsed++;
      await correctionRound(
        note: bestReport.buildCorrectionNote(),
        kind: RecipeRetryKind.compatibility,
        close: () => compatClosed = true,
        // Only a strictly better recipe is kept — the model can "correct"
        // itself into a worse one.
        accept: (candidate, keys) =>
            validateCookingCompatibility(candidate, unknownKeys: keys)
                .flags
                .length <
            bestReport.flags.length,
      );
      continue;
    }

    // 2 — safety (correct-and-regenerate per the signed registry).
    safetyReport = validateRecipeSafety(best!);
    if (safetyReport.hasCorrectable &&
        safetyRetriesUsed < maxSafetyRetries &&
        !safetyClosed) {
      safetyRetriesUsed++;
      await correctionRound(
        note: safetyReport.buildCorrectionNote(),
        kind: RecipeRetryKind.safety,
        close: () => safetyClosed = true,
        accept: (candidate, _) =>
            validateRecipeSafety(candidate).correctable.length <
            safetyReport.correctable.length,
      );
      continue;
    }

    // 3 — allergens (the final say on what is served).
    violations = findAllergenViolations(recipe: best!, avoided: avoidedAllergens);
    if (violations.isNotEmpty &&
        allergenRetriesUsed < maxAllergenRetries &&
        !allergenClosed) {
      allergenRetriesUsed++;
      await correctionRound(
        note: buildAllergenCorrectionNote(violations),
        kind: RecipeRetryKind.allergen,
        close: () => allergenClosed = true,
        accept: (candidate, _) =>
            findAllergenViolations(
                    recipe: candidate, avoided: avoidedAllergens)
                .length <
            violations.length,
      );
      continue;
    }

    break;
  }

  // ── The guarantee. Applied last, unconditionally, to what is served ──────
  final injected = applySafetyInjections(best!);
  best = injected.recipe;

  // Re-read the served recipe so the report describes it rather than the
  // draft that preceded injection, and carry the applied injections.
  final finalFindings = validateRecipeSafety(best!);
  safetyReport = SafetyReport(
    findings: finalFindings.findings,
    injections: injected.injections,
    stepsChecked: finalFindings.stepsChecked,
  );

  final servedWithFlags = !bestReport.isClean;
  final servedWithSafetyFindings = safetyReport.hasCorrectable;

  if (violations.isNotEmpty) {
    // FAIL-OPEN, LOUDLY. Whether this should fail CLOSED instead is argued in
    // docs/DECISIONS.md and is PENDING HARRIS — deliberately not decided
    // here. What is not negotiable is that it is never silent: fail-open is
    // only defensible while the log exists.
    await AllergenFlagLog.record(
      surface: logSurface,
      outcome: 'served_with_violations',
      retriesUsed: allergenRetriesUsed,
      details: violations.map((v) => v.toJson()).toList(),
    );
  }

  await CompatibilityFlagLog.record(
    surface: logSurface,
    report: bestReport,
    retriesUsed: retriesUsed,
    servedWithFlags: servedWithFlags,
  );
  await SafetyFlagLog.record(
    surface: logSurface,
    report: safetyReport,
    retriesUsed: safetyRetriesUsed,
    servedWithFindings: servedWithSafetyFindings,
  );

  return ValidatedRecipeResult(
    recipe: best,
    report: bestReport,
    retriesUsed: retriesUsed,
    servedWithFlags: servedWithFlags,
    safetyReport: safetyReport,
    safetyRetriesUsed: safetyRetriesUsed,
    servedWithSafetyFindings: servedWithSafetyFindings,
    allergenViolations: violations,
    allergenRetriesUsed: allergenRetriesUsed,
  );
}
